#!/bin/python3
import os
import sys
import subprocess
from pathlib import Path
import json
from pprint import pprint
from fnmatch import fnmatch

# static paths
script_path = os.path.abspath(os.path.dirname(__file__))
iso_path = os.path.abspath(script_path + "/iso.nix")
crawler_path = os.path.abspath(script_path + "/config-crawler.nix")


def generate(path: Path, efi_boot=True, query_hardware_config=False):
    nix_configs = list(path.glob("*[nN]ix[cC]onfigs"))
    if not nix_configs:
        print(f"No 'nixConfigs' folder found in '{path}'", file=sys.stderr)
        exit(1)
    nix_configs = nix_configs[0]
    host_data = [
        {"file": config, "config": get_host_information(path, config)}
        for config in get_nix_definitions(nix_configs)
    ]
    print("Generating files")
    for data in host_data:
        folders = generate_folders(path, data)
        folders["iso"].write_text(generate_iso_nix(path, data))
        nixfmt(folders["iso"])
        folders["mini_sys"].write_text(generate_mini_sys(path, data))
        nixfmt(folders["mini_sys"])
        if query_hardware_config:
            print(f"query hardware configuration for {definition_path_to_name(data['file'])}")
            get_hardware_configuration(data, folders["hardware_configuration"])
    hive_nix = path / "generated/hive.nix"
    hive_nix.write_text(generate_hive(path, host_data))
    nixfmt(hive_nix)


def generate_iso_nix(path, host_data):
    mini_sys = generate_folders(path, host_data)["mini_sys"]
    return f"""# This is an auto generated file.
{{pkgs, lib, ... }}:
let
  machine-config =
    import ({crawler_path}) {{
      inherit pkgs lib;
      host-definition = "{host_data["file"]}";
      disko_url = {get_disko_url(path)};
    }};
  disko_source = builtins.fetchTarball {get_disko_url(path)};
  disko_module = "${{disko_source}}/module.nix";
in {{
  imports = [ 
    {iso_path}
    disko_module
    ];
  config = machine-config //{{
    _disko_source = disko_source;
    environment.etc = {{
      "nixos/configuration.nix" = {{ source = {mini_sys}; }};
      "nixos/versions.json" = {{ text = ''{json.dumps(get_versions(path))}''; }};
    }};
    
  }};
}}
"""


def generate_mini_sys(path, host_data):
    # check if a hostID was defined and assign it if so
    host_id = None
    if (
        "networking" in host_data["config"]
        and "hostId" in host_data["config"]["networking"]
    ):
        host_id = host_data["config"]["networking"]["hostId"]
    # format ssh key list for nix
    ssh_keys = ""
    for key in host_data["config"]["admin"]["sshKeys"]:
        ssh_keys += f"\n''{key.strip()}''"
    boot_config = get_boot_information(path, host_data["file"])
    return f"""# This is an auto generated file.
    {{pkgs, lib, config, ... }}:
let
  disko_source = builtins.fetchTarball {get_disko_url(path)};
  disko_module = "${{disko_source}}/module.nix";
in
{{
  imports = [ 
    ./hardware-configuration.nix
    ./modules
    disko_module
  ];
  _disko_source = disko_source;
  boot.loader = builtins.fromJSON ''{json.dumps(boot_config["boot"]["loader"])}'';
  partitioning = builtins.fromJSON ''{json.dumps(host_data["config"]["partitioning"])}'';
  networking.hostName = "{host_data["config"]["networking"]["hostName"]}";
  {f'networking.hostId = "{host_id}";' if host_id else ""}
  interface= "{host_data["config"]["interface"]}";
  ip = "{host_data["config"]["ip"]}";
  admin = {{
    hashedPwd = ''{host_data["config"]["admin"]["hashedPwd"]}'';
    name = "{host_data["config"]["admin"]["name"]}";
    sshKeys = [{ssh_keys}
    ];
  }};
  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = config.services.openssh.ports;
}}
"""


def generate_hive(path, host_data):
    ip_list = "\n".join(
        [
            f"{ip} = {name}"
            for name, ip in generate_ip_list(host_data).items()
            if ip != "dhcp"
        ]
    )
    extra_hosts = f'networking.extraHosts = "{ip_list}";'
    hive_nix = f"""# This is an auto generated file.
      let
        disko_source = builtins.fetchTarball {get_disko_url(path)};
        disko_module = "${{disko_source}}/module.nix";
      in
      {{
        meta.nixpkgs = import (
          builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/{get_versions(path)["nixos"]}.tar.gz"
        ){{}};
      """
    for data in host_data:
        hardware_configuration = generate_folders(path, data)["hardware_configuration"]
        hive_nix += f"""
          {data["config"]["networking"]["hostName"]} = {{
            imports = [ 
              {data["file"]}
              {hardware_configuration}
              disko_module
            ];
            _disko_source = disko_source;
            {extra_hosts}
            deployment = builtins.fromJSON ''{json.dumps(data["config"]["colmena"]["deployment"])}'';
          }};
        """
    hive_nix += "}"
    return hive_nix


def generate_ip_list(host_data):
    ips = {}
    for data in host_data:
        ips[data["config"]["networking"]["hostName"]] = data["config"]["ip"]
    return ips


# get all nix definitions from the directory
# returns all default.nix files from the first folder level
def get_nix_definitions(path):
    nix_files = list(Path(path).glob("*.nix"))  # list all nix files
    nix_files = [(path) for path in nix_files]  # make (filename, path) pairs
    folders = [(path) for path in Path(path).glob("*") if path.is_dir()]
    for folder in [path for path in folders if not (path / "default.nix").exists()]:
        fail_warning = f"Warning: no default.nix found in {folder}; ignoring folder."
        print(fail_warning, file=sys.stderr)
    folders = [
        path / "default.nix" for path in folders if (path / "default.nix").exists()
    ]  # filter folders that have no default.nix
    return nix_files + folders


def generate_folders(path, host_data):
    generation_folder = path / "generated" / definition_path_to_name(host_data["file"])
    generation_folder.mkdir(parents=True, exist_ok=True)
    return {
        "iso": generation_folder / "iso.nix",
        "mini_sys": generation_folder / "mini_sys.nix",
        "hardware_configuration": (generation_folder / "hardware-configuration.nix"),
    }


# returns the folder name from a path with a default nix or the nix file base name
def definition_path_to_name(path):
    path = Path(path)
    if path.name == "default.nix":
        return (path / "..").resolve().name
    if path.is_file():
        return path.stem


def get_host_information(path, nix_definition_file):
    return nix_eval(
        crawler_path,
        args=[
            ("host-definition", nix_definition_file),
            ("disko_url", get_disko_url(path)),
        ],
    )


def get_boot_information(path, nix_definition_file):
    boot_crawler_path = os.path.abspath(script_path + "/boot-crawler.nix")
    return nix_eval(
        boot_crawler_path,
        args=[
            ("host-definition", nix_definition_file),
            ("disko_url", get_disko_url(path)),
        ],
    )


def get_versions(path):
    return json.loads((Path(path) / "versions.json").read_text())


def get_disko_url(path):
    return f"https://github.com/nix-community/disko/archive/{get_versions(path)['disko']}.tar.gz"


def nix_eval(path, attribute="", args=[]):
    args = " ".join(
        [f"--argstr {name} {value}" for (name, value) in args]
    )  # format arguments
    attribute = f"-A {attribute}" if attribute else ""
    cmd = f"nix-instantiate --eval --strict --json {path} {args} {attribute}"
    result = subprocess.run(
        cmd.split(),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Error running '{cmd}': {result.stderr}", file=sys.stderr)
        exit(1)
    else:
        return json.loads(result.stdout.strip())


def nixfmt(file):
    cmd = f"nixfmt {file}"
    result = subprocess.run(
        cmd.split(),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Warning: '{cmd}' failed with: {result.stderr}", file=sys.stderr)


def get_hardware_configuration(host_data, path):
    hostname = host_data["config"]["networking"]["hostName"]
    admin = host_data["config"]["admin"]["name"]
    colmena_target = host_data["config"]["colmena"]["deployment"]["targetHost"]
    address = colmena_target if colmena_target else host_data["config"]["ip"]
    cmd = f"scp {admin}@{address}:/etc/nixos/hardware-configuration.nix {path}"
    warning = (f"Warning: cannot retrieve hardware configuration for host {hostname}",)
    if os.system(cmd) != 0:
        print(warning, file=sys.stderr)


def get_init_token():
    token_path = secrets_dir / "init-token"
    if not token_path.exists():
        print(f"Error: {token_path} does not exists", file=sys.stderr)
        sys.exit(1)
    if not token_path.is_file():
        print(f"Error: {token_path} is not a file", file=sys.stderr)
        sys.exit(1)
    return token_path.read_text()


def get_manifests(path):
    manifests = (path / "manifests").iterdir()
    return [f"{manifest.name}" for manifest in manifests]


def main(path: str = None, efi_boot = True, query_hardware_config = True):
    if path == None:
        path = Path().cwd()
    return generate(Path(path), efi_boot, query_hardware_config)


if __name__ == "__main__":
    path = None
    if len(sys.argv) > 1:
        path = Path(sys.argv[1])
    main(path)
