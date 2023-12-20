use std log

let crawler_path = $"($env.FILE_PWD)/config-crawler-flake.nix"
let boot_crawler_path = $"($env.FILE_PWD)/boot-crawler-flake.nix"
let iso_template_path = $"($env.FILE_PWD)/iso.nix"

# Generates a hive configuration including installation isos in the `generated`folder.
def "main generate" [
  path: directory # The root directory to search for the necessary files
  name? # name of a config in the 'nixConfigs' folder
  --query-hardware-config (-q) = true 
  # Wether to query the hardware configurations from the deployment targets.
  # A hardware configuration is necessary for the final configuration, but can be skipped
  # for iso generation.
] {
  cd $path
  let hive_data = if ($name | is-empty ) {get hive-data} else {get hive-data $name}
  for host in $hive_data {
    let iso_file = ($path | path expand) + "/generated/" + ($host | get name) + "/iso.nix"
    $iso_file | path dirname | mkdir $in
    main generate iso $path ($host | get name) $hive_data | save -f $iso_file
  }
}

export def "main generate iso" [
  path # root configuration path 
  name # name of a config in the 'nixConfigs' folder
  hive_data? # preparsed configuration data
] {
  cd $path
  let hive_data = if ($hive_data | is-empty ) {get hive-data $name} else $hive_data
  let host_data = $hive_data | where name == $name | get 0.config
  let host_file = $hive_data | where name == $name | get 0.file
  let mini_sys_file = ($path | path expand) + "/generated/" + $name + "/mini_sys.nix"
  $mini_sys_file | path dirname | mkdir $in
  main generate mini-sys $path $name $hive_data | save -f $mini_sys_file
  let disko = nix fetch disko
  $"# This is an auto generated file.
  {pkgs, lib, ... }:
  let
    machine-config =
      import ($crawler_path) {
        inherit pkgs lib;
        host-definition = `($host_file)`;
        disko = `($disko)`;
      };
  in {
    imports = [ 
      ($'($disko)/module.nix')
      ($iso_template_path)
      ];
    config = machine-config //{
      _disko_source = ($disko);
      environment.etc = {
        `nixos/configuration.nix` = { source = ($mini_sys_file); };
        `nixos/versions.json` = { text = ''(versions $path)''; };
      };
    };
 }" | str replace -a '`' '"' |  ^nixfmt
}

export def "main generate mini-sys" [
  path # root configuration path 
  name # name of a config in the 'nixConfigs' folder
  hive_data? # preparsed configuration data
  ] {
  cd $path
  let hive_data = if ($hive_data | is-empty ) {get hive-data $name} else $hive_data
  let host_data = $hive_data | where name == $name | get 0.config
  # check if a hostID was defined and assign it if so
  let host_id = try { ($host_data.networking.hostId) }
  # format ssh key list for nix
  let ssh_keys = $host_data.admin.sshKeys | each {|k| $"\n''($k | str trim)''"} | lines | str join
  let disko = nix fetch disko
  $"# This is an auto generated file.
  {pkgs, lib, config, ... }:
  {
    imports = [ 
      ./hardware-configuration.nix
      ./modules
      ($'($disko)/module.nix')
    ];
    _disko_source = ($disko);
    boot.loader = ($host_data.boot.loader | to nix );
    partitioning = ($host_data.partitioning | to nix );
    networking.hostName = `($host_data.networking.hostName)`;
    (if not ($host_id | is-empty) { $'networking.hostId = `($host_id)`;' } else { '' } )
    interface= `($host_data.interface)`;
    ip = `($host_data.ip)`;
    admin = {
      hashedPwd = ''( $host_data.admin.hashedPwd)'';
      name = `($host_data.admin.name)`;
      sshKeys = [($ssh_keys)
      ];
    };
    services.openssh.enable = true;
    networking.firewall.allowedTCPPorts = config.services.openssh.ports;
  }
  " | str replace -a '`' '"' | ^nixfmt
}
 
def piprint [] {
  let msg = $in; print $msg; $msg
}

# def generate_hive(path, host_data):
#     ip_list = "\n".join(
#         [
#             f"{ip} = {name}"
#             for name, ip in generate_ip_list(host_data).items()
#             if ip != "dhcp"
#         ]
#     )
#     extra_hosts = f'networking.extraHosts = "{ip_list}";'
#     hive_nix = f"""# This is an auto generated file.
#       let
#         disko_source = builtins.fetchTarball {get_disko_url(path)};
#         disko_module = "${{disko_source}}/module.nix";
#       in
#       {{
#         meta.nixpkgs = import (
#           builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/{get_versions(path)["nixos"]}.tar.gz"
#         ){{}};
#       """
#     for data in host_data:
#         hardware_configuration = generate_folders(path, data)["hardware_configuration"]
#         hive_nix += f"""
#           {data["config"]["networking"]["hostName"]} = {{
#             imports = [ 
#               {data["file"]}
#               {hardware_configuration}
#               disko_module
#             ];
#             _disko_source = disko_source;
#             {extra_hosts}
#             deployment = builtins.fromJSON ''{json.dumps(data["config"]["colmena"]["deployment"])}'';
#           }};
#         """
#     hive_nix += "}"
#     return hive_nix

def versions [path: directory] { open $"($path)/versions.json" }

def "get host-information" [configFile: path] {
  ^nix-instantiate --eval --strict --json $crawler_path --argstr host-definition $configFile --argstr disko (nix fetch disko) | from json # TODO: nix-shell -p ?
}

def "get boot-information" [configFile: path] {
  ^nix-instantiate --eval --strict --json $boot_crawler_path --argstr host-definition $configFile --argstr disko (nix fetch disko) | from json # TODO: nix-shell -p ?
}

# get all nix definitions from the directory
# returns all default.nix files from the first folder level and all folders with a default.nix
def "get nix-definitions" [path: directory] {
    let nix_files = ls $path | find -r ".*[.]nix" | each {|f| {name: ($f.name | path basename | str substring 0..-4 ), file: $f.name}} # list all nix files
    let folders = ls $path | where type == dir | each {|f|
      if ($"($f.name)/default.nix" | path exists) {
        {name: ($f.name | path basename), file: $"($f.name)/default.nix"}
      } else {
        log warning $"no default.nix found in ($f); ignoring folder."}
    } # list all folders containing a default.nix
    $nix_files ++ $folders
}

def "get hive-data" [
  name?: string # the name of a specific configuration
  ] {
  log info $"Config search path: ($env.PWD)"
  let configPath = glob *[nN]ix[cC]onfigs | get -i 0
  if ($configPath | is-empty ) { 
    log error $"No 'nixConfigs' folder found"; exit 1 }
  let definitions = get nix-definitions $configPath |  if ($name | is-empty) {$in} else {$in | filter {|e| $e.name == $name}}
  $definitions | each {|def| $def | insert config (get host-information $def.file) } | filter {|def| not ($def.config | is-empty) } | each {|def| insert config.boot (get boot-information $def.file).boot}
}

def "main test" [] {
  # cd /home/tom/repos/nix-blueprint
  # get_host_information /home/tom/repos/nix-blueprint/nixConfigs/lianli/default.nix
  fetch-input nixpkgs
}

def "nix fetch" [name] {
  ^nix flake archive --json $name | from json | get path
}

def "nix resolve" [name] {
  ^nix eval --raw $"($env.FILE_PWD)/..#($name)"
}

# convert nuon data to nix
def "to nix" [
  --pretty (-p) # run nixfmt after the conversion
  ] {
  if $pretty {$in | to-nix | ^nixfmt} else {$in | to-nix}
}

def "to-nix" [] {
 match ($in | describe ) {
    $type if ($type | str starts-with "record") => {
      $"{($in | transpose k v | filter {|e| not ($e.v | is-empty)} |
      each {
        |e| $'($e.k | to-nix-id) = ($e.v | to-nix );'
        } | str join)}"
    }
    $type if ($type | str starts-with "list") => ( $"[($in | each {|e| $e | to-nix } | str join ' ')]")
    $type if ($type | str starts-with "table") => {
      log error $"unable to convert table to nix \n ($in | print)"
    }
    "string" => ($in | format-nix-string )
    "bool" => $in
    "int" => $in
    $rest => (log error $"unknown type ($rest)" )
 } 
}

def format-nix-string [] {
  # TODO: better destinguish between the different king of strings
  if ($in | parse -r '.*[-+@"].*' | is-empty) {$'"($in)"'} else {$"''($in)''"}
}

def to-nix-id [] {
  # https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Regular_Expressions/Cheatsheet
  # https://nixos.org/manual/nix/stable/language/values.html#attribute-set
  if ($in | parse -r "[a-zA-Z_][a-zA-Z0-9_'-]*" | length) != 1 {$'"($in)"'} else {$in}
}

# def main [] {
#   "Use --help to print the usage."
# }