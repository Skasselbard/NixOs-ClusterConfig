{
  pkgs,
  lib,
  ...
}:

{
  config.extensions = {

    cluster = {

      options.certificates = (import ./options.nix { inherit pkgs lib; }).options;

      packages = {

        certificates.generate =
          { clusterConfig }:
          let
            this = clusterConfig.clusters.this;
            certData = pkgs.writers.writeJSON "cert-data.json" this.certificates;
            generate-certs = ./generate-certs.sh;
            
          in
          pkgs.writeShellScriptBin "create-certs" ''
            export PATH=$PATH:${pkgs.certstrap}/bin:${pkgs.jq}/bin
            ${pkgs.bash}/bin/bash ${generate-certs} ${certData}
          '';

      };
    };
  };

}
