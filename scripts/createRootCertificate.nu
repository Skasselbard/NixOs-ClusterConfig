use std log

$env.VAULT_ADDR = "http://127.0.0.1:8200"
$env.VAULT_TOKEN = "root"

# load config
let config = $"($env.FILE_PWD)/certConfig.yaml" | open

# populate variables from config
let org = $config | get certData.org
let orgUnit = $config | get certData.orgUnit
let country = $config | get certData.country
let province = $config | get certData.province
let locality = $config | get certData.locality
let domain = $config | get certData.domain
let issuer = $config | get certData.issuer
let role = $config | get role
let rootCertPath = $config | get rootCertPath

let rootCertName = $issuer + "-root"
let intermediateRootCertName = $issuer + "-ca-intermediate-root"
# Script that Follows this Guide:
# https://developer.hashicorp.com/vault/tutorials/secrets-management/pki-engine

module vaultHelpers {
  
# Query vault for all issuer data
  export def getIssuersInfo [endpointPath = "pki"] {
    let issuerKeys = vault list -format=json $"($endpointPath)/issuers" | from json
    if ($issuerKeys | is-empty) {
      []
    } else {
      $issuerKeys | each { |key| vault read -format=json $"($endpointPath)/issuer/($key)" | from json | get data }
    }
  }

  # check pki status
  export def pkiEnabled [endpointPath = "pki"] {
    let secretsStatus = vault secrets list -format=json | from json
    ($endpointPath + "/") in $secretsStatus
  }

  export def importIntermediateCertificate [cert_pem] {
    vault write pki_int/intermediate/set-signed $"certificate=@($cert_pem)"
  }
  
  export def importRootCertificate [pemBundle] {
    # import key
    # vault write /pki/keys/import $"pem_bundle=@($rootCertName).key" $"key_name=($pemBundle)"
    print # make space on stdout to destinguish cmd output
    
    # import pem bundle
    let importedIssuer = vault write -format=json pki/config/ca $"pem_bundle=@($pemBundle)"
    | from json | get data
    print # make space on stdout to destinguish cmd output

    # parse issuer reference
    let issuerRef = if not ($importedIssuer.imported_issuers | is-empty) {
      $importedIssuer.imported_issuers.0
    } else if not ($importedIssuer.existing_issuers  | is-empty) {
      $importedIssuer.existing_issuers.0
    } else {
      log warning "Could not find issuer reference for imported pem bundle"
      return
    }
    
    vault write -format=json $"pki/roles/($role)" allow_any_name=true
    print 
    
    vault write -format=json pki/config/urls $"issuing_certificates=($env.VAULT_ADDR)/v1/pki/ca" $"crl_distribution_points=($env.VAULT_ADDR)/v1/pki/crl"
    print 
    vault patch -format=json $"/pki/issuer/($issuerRef)" $"issuer_name=($intermediateRootCertName)"
  }

}

def createOfflineRootCert [] {
  echo "Creating Offline Root Certificate"
    certstrap --depot-path ($env.PWD) init --organization ($org) --organizational-unit ($orgUnit) --country ($country) --province ($province) --locality ($domain) --common-name $rootCertName --expires "10 year"
    $rootCertName
}

def signIntermediate [rootCA: path, csr: path] {
  certstrap --depot-path ($env.PWD) sign --expires "5 year" --csr $csr --cert $intermediateRootCertName --intermediate --path-length "1" --CA $rootCA  "Intermediate CA1 v1"
}

def createVaultSignedRootCert [] {
  use vaultHelpers *

  # # check if the issuer already exists
  let issuerExists = $rootCertName in (getIssuersInfo | get issuer_name)

  # # Generate the example.com root CA, give it an issuer name, and save its certificate
  if not $issuerExists {
    vault write -field=certificate pki/root/generate/internal $"common_name=($domain)" $"issuer_name=($rootCertName)" ttl=87600h # > out.cert
  }

  # # Create a role for the root CA
  let roleData = (vault write -format=json $"pki/roles/($role)" allow_any_name=true | from json).data

  # # Configure the CA and CRL URLs.
  let urls = (vault write -format=json pki/config/urls $"issuing_certificates=($env.VAULT_ADDR)/v1/pki/ca" $"crl_distribution_points=($env.VAULT_ADDR)/v1/pki/crl" | from json).data
}

def createIntermediateCsr [] {
  use vaultHelpers *

  # check if the issuer already exists
  # let issuerExists = $"($issuer)-intermediate" in (getIssuersInfo "pki_int/" | get issuer_name)

  # if not $issuerExists {
    let tempfile = mktemp --suffix .csr $"($issuer)-XXXXX"
    let csr = (vault write 
      -format=json 
      pki_int/intermediate/generate/exported
      $"common_name=($domain) Intermediate Authority"
      $"issuer_name=($issuer)-intermediate"
    ) | from json | get data.csr | save -f $tempfile
    $tempfile
  # }
}

def createVaultSignedIntermediate [] {
  use vaultHelpers *

  if not (getIssuersInfo | is-empty) {
    try {
    let rootIssuer = (getIssuersInfo | where issuer_name == $intermediateRootCertName).0.issuer_id

    print $rootIssuer
    # check if the issuer already exists
    let issuerExists = $"($issuer)-intermediate" in (getIssuersInfo "pki_int/" | get issuer_name)

    # Generate an intermediate
    if not $issuerExists {
      vault pki issue $"--issuer_name=($issuer)-intermediate" $"/pki/issuer/($rootIssuer)" /pki_int/ $"common_name=($domain)" key_type="rsa" key_bits="4096" max_depth_len=1 $"permitted_dns_domains=($domain)" ttl="43800h"
    }
    } catch { 
      log warning "Could not sign could not find root issuer"
    }
  }
}

def main [] {
  use vaultHelpers *

  cd ($rootCertPath| path expand)

  # Enable the pki secrets engine at the pki path.
  if not (pkiEnabled) {vault secrets enable pki}

  # Enable the pki secrets engine at the pki_int path
  if not (pkiEnabled "pki_int") {vault secrets enable -path=pki_int pki}

  if not ($"($env.PWD)/($rootCertName).crt" | path exists) {
    createOfflineRootCert
  }

  let csr = createIntermediateCsr
  try {
    signIntermediate $rootCertName $csr
    importRootCertificate $intermediateRootCertName
  }
  rm ($env.PWD + "/" + $csr)

  createVaultSignedIntermediate
}

def "main issuerInfo" [] {
  use vaultHelpers *
  getIssuersInfo # pki_int/
}
