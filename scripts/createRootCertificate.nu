use std log

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
let certPath = $config | get certPath

let rootCertName = $config | get rootCert.name
let rootCertPassPhrase = $config | get rootCert.passPhrase
let intermediateCertName = $config | get intermediate.name
let intermediateCertPassPhrase = $config | get intermediate.passPhrase
# Script that Follows this Guide:
# https://developer.hashicorp.com/vault/tutorials/secrets-management/pki-engine

def main [] {

}

def "main createcerts" [] {
  mkdir ($certPath| path expand)
  cd ($certPath| path expand)

  if not ($"($env.PWD)/($rootCertName).crt" | path exists) {
    createOfflineRootCert
  }

  createIntermediateCsr
  signIntermediate $rootCertName ($intermediateCertName + ".csr")
  
}

def "main vault setup" [token] {
  setupVaultEnv $token

  cd ($certPath| path expand)

  setupVaultPki
  vaultImportRootCertificate
}

def "main vault intermediate" [token] {
  setupVaultEnv $token

  # TODO:
  # - create a solid static name configuration
  # - use names for vault configuration
  # - check if vault agent makes connections easier
  # - initialize raft cluster automatically (as far as possible)
  # - write a private script for unsealing
  # - setup machine joining
  # - setup authentication
  # - setup roles
  # - find a way to authenticate linux services
  # - manage secrets for cluster creeation
  createVaultSignedIntermediate
}

def createOfflineRootCert [] {
  log info "Creating Offline Root Certificate"
  (certstrap --depot-path ($env.PWD) init 
    --curve P-256 # ECDSA Signature instead of rsa
    --organization ($org) 
    --organizational-unit ($orgUnit) 
    --country ($country) 
    --province ($province) 
    --locality ($domain) 
    --common-name $rootCertName 
    --expires "10 year" 
    --passphrase $rootCertPassPhrase
    $rootCertName
  )
}

def createIntermediateCsr [] {
  log info "Creating csr to create an intermediate CA signed by the root CA"

  (certstrap --depot-path ($env.PWD) request-cert 
    --curve P-256
    --organization ($org) 
    --organizational-unit ($orgUnit) 
    --country ($country) 
    --province ($province) 
    --locality ($domain) 
    --common-name $intermediateCertName 
    --passphrase $intermediateCertPassPhrase
    --ip "127.0.0.1"
    --domain ($domain)
  )
}

def signIntermediate [rootCA: path, csr: path] {
  log info "Signing CSR with the root CA"

  (certstrap --depot-path ($env.PWD) sign 
    --expires "5 year" 
    --csr $csr 
    --cert ($intermediateCertName + .crt) 
    --intermediate 
    --path-length "1" 
    --CA $rootCA 
    $intermediateCertName
  )

  sudo chown vault:vault ($intermediateCertName + .crt)  ($intermediateCertName + .key)
  sudo chmod 0444 ($intermediateCertName + .crt) 
  sudo chmod 0440 ($intermediateCertName + .key)
}

def vaultImportRootCertificate [] {
  # import key
  vault write /pki/keys/import $"pem_bundle=@($intermediateCertName).key" $"key_name=($intermediateCertName)"
  print # make space on stdout to destinguish cmd output
  
  # import pem bundle
  let importedIssuer = vault write -format=json pki/config/ca $"pem_bundle=@($intermediateCertName).crt"
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
  
  (vault write $"pki/roles/($role)" 
    allow_any_name=true
    allow_localhost=true
  )
  print 
  
  vault write pki/config/urls $"issuing_certificates=($env.VAULT_ADDR)/v1/pki/ca" $"crl_distribution_points=($env.VAULT_ADDR)/v1/pki/crl"
  print 
  vault patch $"/pki/issuer/($issuerRef)" $"issuer_name=($intermediateCertName)"
}

def createVaultSignedRootCert [] {
  # # check if the issuer already exists
  let issuerExists = $rootCertName in (getIssuersInfo | get issuer_name)

  # # Generate the example.com root CA, give it an issuer name, and save its certificate
  if not $issuerExists {
    vault write -field=certificate pki/root/generate/internal $"common_name=($domain)" $"issuer_name=($rootCertName)" ttl=87600h # > out.cert
  }

  # # Create a role for the root CA
  (vault write $"pki/roles/($role)" allow_any_name=true | from json).data

  # # Configure the CA and CRL URLs.
  (vault write pki/config/urls $"issuing_certificates=($env.VAULT_ADDR)/v1/pki/ca" $"crl_distribution_points=($env.VAULT_ADDR)/v1/pki/crl" | from json).data
}


def createVaultSignedIntermediate [] {
  log info ""

  if not (getIssuersInfo | is-empty) {
    try {
    let rootIssuer = (getIssuersInfo | where issuer_name == $intermediateCertName).0.issuer_id

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

def setupVaultPki [] {
  log info "Setting up Vault"

  if not (pkiEnabled) {vault secrets enable pki}
  if not (pkiEnabled "pki_int") {vault secrets enable -path=pki_int pki}
}
  
# Query vault for all issuer data
def getIssuersInfo [endpointPath = "pki"] {
  let issuerKeys = vault list -format=json $"($endpointPath)/issuers" | from json
  if ($issuerKeys | is-empty) {
    []
  } else {
    $issuerKeys | each { |key| vault read -format=json $"($endpointPath)/issuer/($key)" | from json | get data }
  }
}

# check pki status
def pkiEnabled [endpointPath = "pki"] {
  let secretsStatus = vault secrets list -format=json | from json
  ($endpointPath + "/") in $secretsStatus
}

def setupVaultEnv [token] {
  $env.VAULT_ADDR = "https://127.0.0.1:8200"
  $env.VAULT_SKIP_VERIFY = "true" # TODO: import certificate instead
  $env.VAULT_TOKEN = $token
}