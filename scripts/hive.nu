#!/usr/bin/env nu

source generate.nu

# Initialize a directory.
#
# Creates the expected folders and a versions.json file
def "main setup" [
    --path (-p): directory # The root directory to search for the necessary files
] {
  mkdir ($path + /nixConfigs)
  mkdir ($path + /manifests)
  mkdir ($path + /generated)
  # TODO: flake init template
  {
    "nixos": "nixos-23.05",
    "k3s": "v1.27.4-k3s1",
    "disko": "v1.1.0"
  } | save ($path + /versions.json)
}

# Genarate the Stage-0 image to setup the machine.
#
# If given a device, the generated image will be copied there with `dd`.
def "main iso" [
  --path (-p): directory # The root directory to search for the necessary files. Needs a flake.nix with nixpkgs in the inputs
  --skip-generate (-s) # Skips the automatic regeneration of the hive.nix
  --name (-n): string # Name of the nix configuration for which the iso should be build
  --device (-d): directory # Path to the device where the image should be copied to. Copy is skipped if the flag is empty.
] {
  let path = if $path != null {$path } else {$env.PWD}
  if not $skip_generate {main generate $path}
  ^nix run "nixpkgs#nixos-generators" -- --format iso --configuration $"($path)/generated/($name)/iso.nix" -o $"($path)/generated/($name)/iso" -I $"nixpkgs=https://github.com/NixOS/nixpkgs/archive/(open ($path + /versions.json) | get nixos ).tar.gz"
  if $env.LAST_EXIT_CODE == 0 and $device != null {
    ^sudo dd $"if=($path)/generated/($name)/iso/iso/nixos.iso" $"of=($device)" bs=4M conv=fsync status=progress
  } else {"error"}
}


# Run colmena apply wrapped in a the staged-hive environment
def --wrapped "main apply" [
  --path (-p): directory # The root directory to search for the necessary files
  --skip-generate (-s) # skips the automatic regeneration of the hive.nix
  --colmena-help # run colmenas help command
  ...colmena_args # arguments passed to colmena
  ]  {
  if not $skip_generate {main generate $path}
  colmena apply $colmena_help $path ($colmena_args | str join " ")
}

# Run colmena apply-local wrapped in a the staged-hive environment
def --wrapped "main apply-local" [
  --path (-p): directory # The root directory to search for the necessary files
  --skip-generate (-s) # skips the automatic regeneration of the hive.nix
  --colmena-help # run colmenas help command
  ...colmena_args # arguments passed to colmena
  ]  {
  if not $skip_generate {main generate $path}
  colmena apply-local $colmena_help $path ($colmena_args | str join " ")
}

# Run colmena build wrapped in a the staged-hive environment
def --wrapped "main build" [
  --path (-p): directory # The root directory to search for the necessary files
  --skip-generate (-s) # skips the automatic regeneration of the hive.nix
  --colmena-help # run colmenas help command
  ...colmena_args # arguments passed to colmena
  ]  {
  if not $skip_generate {main generate $path}
  colmena build $colmena_help $path ($colmena_args | str join " ")
}

# Run colmena eval wrapped in a the staged-hive environment
def --wrapped "main eval" [
  --path (-p): directory # The root directory to search for the necessary files
  --skip-generate (-s) # skips the automatic regeneration of the hive.nix
  --colmena-help # run colmenas help command
  ...colmena_args # arguments passed to colmena
  ]  {
  if not $skip_generate {main generate $path}
  colmena eval $colmena_help $path ($colmena_args | str join " ")
}

# Run colmena upload-keys wrapped in a the staged-hive environment
def --wrapped "main upload-keys" [
  --path (-p): directory # The root directory to search for the necessary files
  --skip-generate (-s) # skips the automatic regeneration of the hive.nix
  --colmena-help # run colmenas help command
  ...colmena_args # arguments passed to colmena
  ]  {
  if not $skip_generate {main generate $path}
    colmena upload-keys $colmena_help $path ($colmena_args | str join " ")
}

# Run colmena exec wrapped in a the staged-hive environment
def --wrapped "main exec" [
  --path (-p): directory # The root directory to search for the necessary files
  --skip-generate (-s) # skips the automatic regeneration of the hive.nix
  --colmena-help # run colmenas help command
  ...colmena_args # arguments passed to colmena
  ]  {
  if not $skip_generate {main generate $path}
  colmena exec $colmena_help $path ($colmena_args | str join " ")
}

# Run colmena repl wrapped in a the staged-hive environment
def --wrapped "main repl" [
  --path (-p): directory # The root directory to search for the necessary files
  --skip-generate (-s) # skips the automatic regeneration of the hive.nix
  --colmena-help # run colmenas help command
  ...colmena_args # arguments passed to colmena
  ]  {
  if not $skip_generate {main generate $path}
  colmena repl $colmena_help $path ($colmena_args | str join " ")
}

# Run colmena nix-info wrapped in a the staged-hive environment
def --wrapped "main nix-info" [
  --path (-p): directory # The root directory to search for the necessary files
  --skip-generate (-s) # skips the automatic regeneration of the hive.nix
  --colmena-help # run colmenas help command
  ...colmena_args # arguments passed to colmena
  ]  {
  if not $skip_generate {main generate $path}
  colmena nix-info $colmena_help $path ($colmena_args | str join " ")
}

def --wrapped colmena [subcommand chelp:bool hive_path: directory ...args] {
  if $chelp {
      nix-shell -p colmena --run $"colmena ($subcommand) --help"
  } else {
    let path = if $hive_path != null {$hive_path } else {$env.PWD}
    let path = $path + /generated/hive.nix
    nix-shell -p colmena --run $"colmena -f ($path) ($subcommand) ($args|str join ' ')"
  }
}

def print-main-help [] {
  help "main build"
}

# Setup a Colmena hive from a set of nix configs.
#
# Use the subcommands to access the functionality.
# Includes a wrapper around colmena.
def main [
  --path (-p): directory # The root directory to search for the necessary files
  ] {
    help main # nushell bug? Type --help (-- --help for nix flake use) to get a usage example
    null
}
