{
  pkgs,
  lib,
  flakeInputs,
  ...
}:

let # imports
  mkOption = lib.mkOption;

  nullOr = lib.types.nullOr;
  either = lib.types.either;
  package = lib.types.package;
  enum = lib.types.enum;

  nixos-anywhere = flakeInputs.nixos-anywhere;

  getFormatScript =
    { clusterConfig }:
    let
      this = clusterConfig.clusters.this.nodes.this;
      deploymentConfig = this.deployment;
      nodeConfig = this.config;
    in
    if deploymentConfig.formatScript == null then
      (pkgs.writeScript "formatScript" ''echo "skip formatting"'')
    else if deploymentConfig.formatScript == "disko" then
      (pkgs.writeScript "formatScript" nodeConfig.disko.devices._disko)
    else
      deploymentConfig.formatScript;
in
{
  config.extensions = {

    nodes = {

      options.deployment.formatScript = mkOption {
        description = ''
          Used to format drives during a nixos-anywhere deployment and to format remotely on demand.

          If set to `null` no format script will be executed while deploying nixos anywhere.
          If set to `"disko"` the default [disko](https://github.com/nix-community/disko) format script generated from the disko devices is run.
          If set to a executable script, this script is run.

          Nixos Anywhere can be run with `nix run .#hostname.create`.
          Additionally, the format script can be run remotly with `nix run .#hostname.format`.
        '';
        type = nullOr (either package (enum [ "disko" ]));
        default = null;
      };

      packages = {

        create =
          { clusterConfig }:
          let
            this = clusterConfig.clusters.this.nodes.this;
            nodeName = this.name;
            deploymentConfig = this.deployment;
            nixosConfig = this.config.system.build.toplevel.outPath;
            formatScript = getFormatScript { inherit clusterConfig; };
          in
          pkgs.writeShellScriptBin "create-${nodeName}" ''
            ${pkgs.nix}/bin/nix run path:${nixos-anywhere.outPath} -- -s ${formatScript.outPath} ${nixosConfig} ${deploymentConfig.targetUser}@${deploymentConfig.targetHost}
          '';

        format =
          { clusterConfig }:
          let
            this = clusterConfig.clusters.this.nodes.this;
            nodeName = this.name;
            formatScript = getFormatScript { inherit clusterConfig; };
            ip = this.deployment.targetHost;
            sshArgs = [ "-t" ];
          in
          if this.deployment.formatScript == null then
            pkgs.writeShellScriptBin "format-${nodeName}" "echo no format script configured"
          else
            pkgs.writeShellScriptBin "deploy" ''
              echo "Run format script on host ${nodeName}?"
              echo "WARNING: disk content will be erased if you select yes!"
              [[ ! "$(read -e -p "Y/n> "; echo $REPLY)" == [Yy]* ]] &&  echo "Canceld formating disko config." && exit
              echo "Formatting ${nodeName}."
              script=$(${pkgs.nix}/bin/nix build ${formatScript} --print-out-paths)

              ${pkgs.nix}/bin/nix copy --to "ssh://root@${ip}" "$script"
              ssh ${builtins.concatStringsSep " " sshArgs} root@${ip} $script
            '';

      };
    };
  };

}
