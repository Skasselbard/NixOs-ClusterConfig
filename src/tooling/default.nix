{
  pkgs,
  lib ? pkgs.lib,
}:

let
  tool = pkgs.writeShellApplication {
    name = "clusterConfig";
    runtimeInputs = [
      pkgs.nix
      pkgs.jq
      pkgs.fzf
      pkgs.coreutils
      pkgs.git
      pkgs.gawk
      pkgs.util-linux
    ];
    text = builtins.readFile ./clusterConfig.sh;
  };

  completionFiles = pkgs.runCommand "clusterConfig-completions" { } ''
    mkdir -p \
      $out/share/bash-completion/completions \
      $out/share/zsh/site-functions \
      $out/share/fish/vendor_completions.d \
      $out/share/nushell
    ${tool}/bin/clusterConfig completions bash > $out/share/bash-completion/completions/clusterConfig
    ${tool}/bin/clusterConfig completions zsh > $out/share/zsh/site-functions/_clusterConfig
    ${tool}/bin/clusterConfig completions fish > $out/share/fish/vendor_completions.d/clusterConfig.fish
    ${tool}/bin/clusterConfig completions nu > $out/share/nushell/clusterConfig.nu
  '';
in
pkgs.symlinkJoin {
  name = "clusterConfig";
  paths = [
    tool
    completionFiles
  ];
  postBuild = ''
    ln -s ${tool}/bin/clusterConfig $out/bin/clcli
  '';
}
