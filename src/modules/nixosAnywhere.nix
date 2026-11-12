{
  pkgs,
  lib,
  clusterlib,
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

    };
    machines.packages = {
      create = {
        description = "Install NixOS on the target host with nixos-anywhere";
        destructive = true;
        package =
          { clusterConfig }:
          let
            this = clusterConfig.clusters.this.nodes.this;
          nodeName = this.name;
          deploymentConfig = this.deployment;
          host =
            if deploymentConfig.targetHost == null then
              throw "clusterConfig: ${nodeName} has no remote targetHost"
            else if deploymentConfig.targetHost == "{hostname}" then
              nodeName
            else
              deploymentConfig.targetHost;
          target =
            (lib.optionalString (deploymentConfig.targetUser != null) "${deploymentConfig.targetUser}@") + host;
          port = lib.optionalString (
            deploymentConfig.targetPort != null
          ) "--ssh-port ${toString deploymentConfig.targetPort}";
          nixosConfig = this.config.system.build.toplevel.outPath;
          formatScript = getFormatScript { inherit clusterConfig; };
          extraFiles = this.deployment.extraFiles;
          extraFileSetup = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              extraTarget: entry:
              let
                hasSource = (entry.source or null) != null;
                hasCommand = (entry.command or null) != null;
                sourceCommand =
                  if hasSource == hasCommand then
                    throw "deployment.extraFiles.${extraTarget} must set exactly one of source or command"
                  else if !lib.hasPrefix "/" extraTarget || builtins.elem ".." (lib.splitString "/" extraTarget) then
                    throw "deployment.extraFiles.${extraTarget} must be an absolute path without '..'"
                  else if hasSource then
                    "cp -- ${lib.escapeShellArg entry.source} \"$tmp_extra_dir\"${lib.escapeShellArg extraTarget}"
                  else
                    "${entry.command} > \"$tmp_extra_dir\"${lib.escapeShellArg extraTarget}";
              in
              ''
                mkdir -p "$tmp_extra_dir$(dirname ${lib.escapeShellArg extraTarget})"
                ${sourceCommand}
                chmod ${lib.escapeShellArg (entry.mode or "0400")} "$tmp_extra_dir"${lib.escapeShellArg extraTarget}
              ''
            ) extraFiles
          );
          in
          pkgs.writeShellScriptBin "create" ''
          set -euo pipefail
          extra_files=()
          tmp_extra_dir=""
          cleanup() { [ -z "$tmp_extra_dir" ] || rm -rf "$tmp_extra_dir"; }
          trap cleanup EXIT
          ${
            if extraFiles == { } then
              ""
            else
              ''
                tmp_extra_dir="$(mktemp -d)"
                ${extraFileSetup}
                extra_files=(--extra-files "$tmp_extra_dir")
              ''
          }
          ${pkgs.nix}/bin/nix run path:${nixos-anywhere.outPath} -- -s ${formatScript.outPath} ${nixosConfig} ${port} "''${extra_files[@]}" ${lib.escapeShellArg target} "$@"
        '';
      };

      format = {
        description = "Run the configured disk format script on the target host";
        destructive = true;
        package =
          { clusterConfig }:
          let
            this = clusterConfig.clusters.this.nodes.this;
          nodeName = this.name;
          formatScript = getFormatScript { inherit clusterConfig; };
          cfg = this.deployment;
          host =
            if cfg.targetHost == null then
              throw "clusterConfig: ${nodeName} has no remote targetHost"
            else if cfg.targetHost == "{hostname}" then
              nodeName
            else
              cfg.targetHost;
          target = (lib.optionalString (cfg.targetUser != null) "${cfg.targetUser}@") + host;
          port = lib.optionalString (cfg.targetPort != null) "-p ${toString cfg.targetPort}";
          uriHost = if lib.hasInfix ":" host then "[${host}]" else host;
          uri = "ssh://${lib.optionalString (cfg.targetUser != null) "${cfg.targetUser}@"}${uriHost}${
            lib.optionalString (cfg.targetPort != null) ":${toString cfg.targetPort}"
          }";
          in
          if this.deployment.formatScript == null then
            pkgs.writeShellScriptBin "format" "echo no format script configured"
          else
            pkgs.writeShellScriptBin "format" ''
              echo "Run format script on host ${nodeName}?"
              echo "WARNING: disk content will be erased if you select yes!"
              [[ ! "$(read -e -p "Y/n> "; echo $REPLY)" == [Yy]* ]] && echo "Cancelled formatting." && exit
              echo "Formatting ${nodeName}."
              script=$(${pkgs.nix}/bin/nix build ${formatScript} --print-out-paths)

              ${pkgs.nix}/bin/nix copy --to ${lib.escapeShellArg uri} "$script"
              ${pkgs.openssh}/bin/ssh ${port} -t ${lib.escapeShellArg target} "$script"
            '';
      };
    };
  };
}
