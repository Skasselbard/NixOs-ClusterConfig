export def info [] {
  ^nix eval $".#clusterInfo" --json | from json

}