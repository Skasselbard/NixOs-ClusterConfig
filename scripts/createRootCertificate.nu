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
let rootCertName = $config | get rootCertName

# Script that Follows this Guide:
# https://developer.hashicorp.com/vault/tutorials/secrets-management/pki-engine

# Query vault for all issuer data
def getIssuersInfo [endpointPath = "pki/"] {
  let issuerKeys = vault list -format=json $"($endpointPath)/issuers" | from json
  $issuerKeys | each { |key| vault read -format=json $"($endpointPath)/issuer/($key)" | from json | get data }
}

# check pki status
def pkiEnabled [endpointPath = "pki/"] {
  let secretsStatus = vault secrets list -format=json | from json
  $endpointPath in $secretsStatus
}

def createOfflineRootCert [] {
  let outpath = $rootCertPath | path expand
  if not ($"($outpath)/($issuer)-root.crt" | path exists) {
    certstrap --depot-path ($outpath) init --organization ($org) --organizational-unit ($orgUnit) --country ($country) --province ($province) --locality ($domain) --common-name $"($issuer)-root"
    $"($issuer)-root"
  } else {
    $rootCertName
  }
}

def createSelfSignedRootCert [] {
  # # Enable the pki secrets engine at the pki path.
  if not (pkiEnabled) {vault secrets enable pki}

  # # check if the issuer already exists
  let issuerExists = $"($issuer)-root" in (getIssuersInfo | get issuer_name)

  # # Generate the example.com root CA, give it an issuer name, and save its certificate
  if not $issuerExists {
    vault write -field=certificate pki/root/generate/internal $"common_name=($domain)" $"issuer_name=($issuer)-root" ttl=87600h # > out.cert
  }

  # # Create a role for the root CA
  let roleData = (vault write -format=json $"pki/roles/($role)" allow_any_name=true | from json).data

  # # Configure the CA and CRL URLs.
  let urls = (vault write -format=json pki/config/urls $"issuing_certificates=($env.VAULT_ADDR)/v1/pki/ca" $"crl_distribution_points=($env.VAULT_ADDR)/v1/pki/crl" | from json).data
}

def createIntermediateCsr [] {
  # Enable the pki secrets engine at the pki_int path
  if not (pkiEnabled "pki_int/") {vault secrets enable -path=pki_int pki}

  # check if the issuer already exists
  # let issuerExists = $"($issuer)-intermediate" in (getIssuersInfo "pki_int/" | get issuer_name)

  # if not $issuerExists {
    let tempfile = mktemp --suffix .csr $"($issuer)-XXXXX"
    let csr = (vault write 
      -format=json 
      pki_int/intermediate/generate/internal
      common_name=$"($domain) Intermediate Authority"
      issuer_name=$"($issuer)-intermediate"
    ) | from json | get data.csr | save -f $tempfile
    $tempfile
  # }
}

def signIntermediate [rootCA: path, csr: path] {
  let outpath = $rootCertPath | path expand
  certstrap --depot-path ($outpath) sign --expires "3 year" --csr $csr --cert $"($issuer)-ca-root" --intermediate --path-length "1" --CA $rootCA  "Intermediate CA1 v1"
}

def main [] {
  let choice = input -n 1 "Create root certificate? Y/N\n>"
  let certname = if ($choice | str downcase) == 'y' {
    createOfflineRootCert
  } else {
    $rootCertName 
  }
  let csr = createIntermediateCsr
  try {
    signIntermediate $certname $csr
    hier gehts weiter
  }
  rm $csr
}


# # Enable the pki secrets engine at the pki_int path
# if not (pkiEnabled "pki_int/") {vault secrets enable -path=pki_int pki}

# let rootIssuer = (getIssuersInfo | where issuer_name == $"($issuer)-root").0.issuer_id

# # check if the issuer already exists
# let issuerExists = $"($issuer)-intermediate" in (getIssuersInfo "pki_int/" | get issuer_name)

# # Generate an intermediate
# if not $issuerExists {
#   vault pki issue $"--issuer_name=($issuer)-intermediate" $"/pki/issuer/($rootIssuer)" /pki_int/ $"common_name=($domain)" key_type="rsa" key_bits="4096" max_depth_len=1 $"permitted_dns_domains=($domain)" ttl="43800h"
# }