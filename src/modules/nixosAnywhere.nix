{
  pkgs,
  lib,
  clusterlib,
  nixos-anywhere,
  ...
}:

let # imports
  add = clusterlib.add;

  mkOption = lib.mkOption;

  nullOr = lib.types.nullOr;
  either = lib.types.either;
  package = lib.types.package;
  enum = lib.types.enum;

  # redefine types to nest submodules at the right place
  domainType = clusterlib.domainType { inherit clusterType; };
  clusterType = clusterlib.clusterType { inherit machineType; };

  # defining deployment options for machines
  machineType.options.deployment = {
    # TODO:
    formatScript = mkOption {
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
  };

  # Build nixos-anywhere setup script for remote installations in packages.$system.$machineName.create
  deploymentAnnotation =
    config:
    add.machinePackages config (
      machineName: machineConfig: _config:
      let
        cfg = machineConfig.nixosConfiguration.config;
        nixosConfig = cfg.system.build.toplevel.outPath;
        formatScript = # -
          if machineConfig.deployment.formatScript == null then
            (pkgs.writeScript "formatScript" ''echo "skip formatting"'')
          else if machineConfig.deployment.formatScript == "disko" then
            (pkgs.writeScript "formatScript" cfg.disko.devices._disko)
          else
            machineConfig.deployment.formatScript;
      in
      {
        create = pkgs.writeScriptBin "create-${machineName}" ''
          ${pkgs.nix}/bin/nix run path:${nixos-anywhere.outPath} -- -s ${formatScript.outPath} ${nixosConfig} ${machineConfig.deployment.targetUser}@${machineConfig.deployment.targetHost}
        '';
        format =
          if machineConfig.deployment.formatScript == null then
            pkgs.writeScriptBin "format-${machineName}" "echo no format script configured"
          else
            let
              ip = machineConfig.deployment.targetHost;
              sshArgs = [ "-t" ];
              script = formatScript;
            in
            pkgs.writeScriptBin "deploy" ''
              echo "Run format script on host ${machineName}?"
              echo "WARNING: disk content will be erased if you select yes!"
              [[ ! "$(read -e -p "Y/n> "; echo $REPLY)" == [Yy]* ]] &&  echo "Canceld formating disko config." && exit
              echo "Formatting ${machineName}."
              script=$(${pkgs.nix}/bin/nix build ${script} --print-out-paths)

              ${pkgs.nix}/bin/nix copy --to "ssh://root@${ip}" "$script"
              ssh ${builtins.concatStringsSep " " sshArgs} root@${ip} $script
            '';
      }
    );
in
{

  options.domain = domainType;
  config.extensions.deploymentTransformations = [ deploymentAnnotation ];
}
