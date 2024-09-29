use std log

# Script that Follows this Guide:
# https://developer.hashicorp.com/vault/tutorials/secrets-management/pki-engine

def main [] {
print "test"
}

def "main create cert root" [configJson] {
  let config = $configJson | from json

  mkdir ($config.certPath| path expand)
  cd ($config.certPath| path expand)

  let rootCaPath = $"($env.PWD)/($config.rootCert.name).crt"

  if not ($rootCaPath| path exists) {
    createOfflineRootCert $config
  } else {
    log warning ("Root certificate under: '" + $rootCaPath + "' already exists. skipping creation")
  }
  
}

def "main create cert intermediate" [configJson] {
  let config = $configJson | from json

  mkdir ($config.certPath| path expand)
  cd ($config.certPath| path expand)

  let rootCaPath = $"($env.PWD)/($config.rootCert.name).crt"
  let intermediateCaPath = $"($env.PWD)/($config.intermediate.name).crt"

  if not ($rootCaPath | path exists) {
    log error ("Root certificate not found under: " + $rootCaPath)
    exit 1
  }

  if not ($intermediateCaPath| path exists) {
    createIntermediateCsr $config
    signIntermediate $config   
    } else {
    log warning ("Intermediate certificate under: '" + $intermediateCaPath + "' already exists. skipping creation")
  }

}


# def parseConfig [json] {

# # populate variables from config
# # {
# # let org = $json | get certData.org
# # let orgUnit = $json | get certData.orgUnit
# # let country = $json | get certData.country
# # let province = $json | get certData.province
# # let locality = $json | get certData.locality
# # let domain = $json | get certData.domain
# # let issuer = $json | get certData.issuer
# # let role = $json | get role
# # let certPath = $json | get certPath

# # let rootCertName = $json | get rootCert.name
# # let rootCertPassPhrase = $json | get rootCert.passPhrase
# # let intermediateCertName = $json | get intermediate.name
# # let intermediateCertPassPhrase = $json | get intermediate.passPhrase
# # }
# from json
# }

def "main vault setup" [token configJson] {
  let config = $configJson | from json

  setupVaultEnv $token

  cd ($config.certPath| path expand)

  setupVaultPki
  vaultImportRootCertificate $config
}

def "main vault intermediate" [token configJson] {
  let config = $configJson | from json

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
  # - manage secrets for cluster creation
  createVaultSignedIntermediate $config
}

def createOfflineRootCert [config] {
  log info "Creating Offline Root Certificate"
  (certstrap --depot-path ($env.PWD) init 
    --curve P-256 # ECDSA Signature instead of rsa
    --organization ($config.certData.org) 
    --organizational-unit ($config.certData.orgUnit) 
    --country ($config.certData.country) 
    --province ($config.certData.province) 
    --locality ($config.certData.locality) 
    --common-name $config.rootCert.name 
    --expires "10 year" 
    --passphrase $config.rootCert.passPhrase
    $config.rootCert.name
  )
}

def createIntermediateCsr [config] {
  log info "Creating csr to create an intermediate CA signed by the root CA"

  (certstrap --depot-path ($env.PWD) request-cert 
    --curve P-256
    --organization ($config.certData.org) 
    --organizational-unit ($config.certData.orgUnit) 
    --country ($config.certData.country) 
    --province ($config.certData.province) 
    --locality ($config.certData.locality) 
    --common-name $config.intermediate.name 
    --passphrase $config.intermediate.passPhrase
    --ip "127.0.0.1"
    --domain ($config.certData.domain)
  )
}

def signIntermediate [config] {
  
  log info "Signing CSR with the root CA"

  (certstrap --depot-path ($env.PWD) sign 
    --expires "5 year" 
    --csr ($config.intermediate.name + ".csr") 
    --cert ($config.intermediate.name + .crt) 
    --intermediate 
    --path-length "1" 
    --CA $config.rootCert.name 
    $config.intermediate.name
  )

  sudo chown vault:vault ($config.intermediate.name + .crt)  ($config.intermediate.name + .key)
  sudo chmod 0444 ($config.intermediate.name + .crt) 
  sudo chmod 0440 ($config.intermediate.name + .key)
}

def vaultImportRootCertificate [config] {
  # import key
  vault write /pki/keys/import $"pem_bundle=@($config.intermediate.name).key" $"key_name=($config.intermediate.name)"
  print # make space on stdout to destinguish cmd output
  
  # import pem bundle
  let importedIssuer = vault write -format=json pki/config/ca $"pem_bundle=@($config.intermediate.name).crt"
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
  
  (vault write $"pki/roles/($config.role)" 
    allow_any_name=true
    allow_localhost=true
  )
  print 
  
  vault write pki/config/urls $"issuing_certificates=($env.VAULT_ADDR)/v1/pki/ca" $"crl_distribution_points=($env.VAULT_ADDR)/v1/pki/crl"
  print 
  vault patch $"/pki/issuer/($issuerRef)" $"issuer_name=($config.intermediate.name)"
}

def createVaultSignedRootCert [config] {
  # # check if the issuer already exists
  let issuerExists = $config.rootCert.name in (getIssuersInfo | get issuer_name)

  # # Generate the example.com root CA, give it an issuer name, and save its certificate
  if not $issuerExists {
    vault write -field=certificate pki/root/generate/internal $"common_name=($config.certData.domain)" $"issuer_name=($config.rootCert.name)" ttl=87600h # > out.cert
  }

  # # Create a role for the root CA
  (vault write $"pki/roles/($config.role)" allow_any_name=true | from json).data

  # # Configure the CA and CRL URLs.
  (vault write pki/config/urls $"issuing_certificates=($env.VAULT_ADDR)/v1/pki/ca" $"crl_distribution_points=($env.VAULT_ADDR)/v1/pki/crl" | from json).data
}


def createVaultSignedIntermediate [config] {
  log info ""

  if not (getIssuersInfo | is-empty) {
    try {
    let rootIssuer = (getIssuersInfo | where issuer_name == $config.intermediate.name).0.issuer_id

    print $rootIssuer
    # check if the issuer already exists
    let issuerExists = $"($config.certData.issuer)-intermediate" in (getIssuersInfo "pki_int/" | get issuer_name)

    # Generate an intermediate
    if not $issuerExists {
      vault pki issue $"--issuer_name=($config.certData.issuer)-intermediate" $"/pki/issuer/($rootIssuer)" /pki_int/ $"common_name=($config.certData.domain)" key_type="rsa" key_bits="4096" max_depth_len=1 $"permitted_dns_domains=($config.certData.domain)" ttl="43800h"
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