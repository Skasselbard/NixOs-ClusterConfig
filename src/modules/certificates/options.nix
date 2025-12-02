{ lib, ... }:

with lib;

let
  str = lib.types.str;
  nullOr = lib.types.nullOr;

  curveAlgorithms = [
    "P-224"
    "P-256"
    "P-384"
    "P-521"
    "Ed25519"
  ];

  # per-certificate definition
  certDefType = types.submodule {
    options = {
      commonName = mkOption {
        type = str;
        description = "Subject Common Name (CN).";
      };
      domains = mkOption {
        type = types.listOf str;
        default = [ ];
        description = "DNS SubjectAltNames.";
      };
      ips = mkOption {
        type = types.listOf str;
        default = [ ];
        description = "IP SubjectAltNames.";
      };
      uri = mkOption {
        type = types.listOf str;
        default = [ ];
        description = "URI SubjectAltNames.";
      };
      passPhrase = mkOption {
        type = str;
        default = "";
        description = "Optional passphrase for the key (unused by default).";
      };
      expires = mkOption {
        type = str;
        default = "5 year";
        description = "certstrap expiry string e.g. '5 year'";
      };
      organization = mkOption {
        type = nullOr str;
        example = "ExampleOrg";
        default = null;
      };
      organizationalUnit = mkOption {
        type = nullOr str;
        example = "IT";
        default = null;
      };
      country = mkOption {
        type = nullOr str;
        example = "DE";
        default = null;
      };
      province = mkOption {
        type = nullOr str;
        example = "Bundesland";
        default = null;
      };
      locality = mkOption {
        type = nullOr str;
        example = "TownStadt";
        default = null;
      };
      curve = mkOption {
        type = types.enum curveAlgorithms;
        default = "P-256";
        description = "Elliptic curve for key generation (P-256 etc.)";
      };
      keyPerm = mkOption {
        type = str;
        default = "0400";
        description = "File mode for the private key.";
      };
      certPerm = mkOption {
        type = str;
        default = "0444";
        description = "File mode for public certs.";
      };
      signedBy = mkOption {
        type = types.listOf str;
        description = "Parent CA name (root or intermediate)";
      };
    };
  };

  caDefType = types.submodule {
    options = {
      commonName = mkOption {
        type = str;
      };
      passPhrase = mkOption {
        type = str;
        default = "";
      };
      expires = mkOption {
        type = str;
        default = "10 year";
      };
      curve = mkOption {
        type = types.enum curveAlgorithms;
        default = "P-256";
      };
      organization = mkOption {
        type = nullOr str;
        example = "ExampleOrg";
        default = null;
      };
      organizationalUnit = mkOption {
        type = nullOr str;
        example = "IT";
        default = null;
      };
      country = mkOption {
        type = nullOr str;
        example = "DE";
        default = null;
      };
      province = mkOption {
        type = nullOr str;
        example = "Bundesland";
        default = null;
      };
      locality = mkOption {
        type = nullOr str;
        example = "TownStadt";
        default = null;
      };
      permitDomains = mkOption {
        type = types.listOf str;
        default = [ ];
      };
      pathLength = mkOption {
        type = types.nullOr types.int;
        default = null;
      };
    };
  };

  intermediateDefType = types.submodule {
    options = {
      commonName = mkOption {
        type = str;
      };
      domains = mkOption {
        type = types.listOf str;
        default = [ ];
        description = "DNS SubjectAltNames.";
      };
      ips = mkOption {
        type = types.listOf str;
        default = [ ];
        description = "IP SubjectAltNames.";
      };
      uri = mkOption {
        type = types.listOf str;
        default = [ ];
        description = "URI SubjectAltNames.";
      };
      passPhrase = mkOption {
        type = str;
        default = "";
      };
      expires = mkOption {
        type = str;
        default = "10 year";
      };
      curve = mkOption {
        type = types.enum curveAlgorithms;
        default = "P-256";
      };
      organization = mkOption {
        type = nullOr str;
        example = "ExampleOrg";
        default = null;
      };
      organizationalUnit = mkOption {
        type = nullOr str;
        example = "IT";
        default = null;
      };
      country = mkOption {
        type = nullOr str;
        example = "DE";
        default = null;
      };
      province = mkOption {
        type = nullOr str;
        example = "Bundesland";
        default = null;
      };
      locality = mkOption {
        type = nullOr str;
        example = "TownStadt";
        default = null;
      };
      pathLength = mkOption {
        type = types.nullOr types.int;
        default = null;
      };
      keyPerm = mkOption {
        type = str;
        default = "0400";
        description = "File mode for the private key.";
      };
      certPerm = mkOption {
        type = str;
        default = "0444";
        description = "File mode for public certs.";
      };
      signedBy = mkOption {
        type = types.listOf str;
        description = "Parent CA name (root or intermediate)";
      };
    };
  };
in
{

  options = {

    outDir = mkOption {
      type = types.str;
      default = "./certificates";
      description = "Base output directory. Structure: outDir/<set>/{ca,intermediates,certs}";
    };

    sets = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = true;
            };
            outSubpath = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "optional subpath under outDir (defaults to set name)";
            };

            ca = mkOption {
              type = caDefType;
              default = {
                commonName = "root";
              };
            };

            intermediates = mkOption {
              type = types.attrsOf intermediateDefType;
              default = { };
              description = "optional intermediate CAs. parentCA refers to a CA name";
            };

            certs = mkOption {
              type = types.attrsOf certDefType;
              default = { };
              description = "Leaf certificates to generate for this set; attribute name is arbitrary (e.g. apiserver, kubelet-node1).";
            };
          };
        }
      );
      default = { };
      description = "Certificate sets such as 'kubernetes', 'etcd', 'vault'.";
    };
  };

}
