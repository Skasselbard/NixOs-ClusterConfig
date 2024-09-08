export def info [] {
  ^nix eval ".#clusterConfig.domain" #--json | from json
}