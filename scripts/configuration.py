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
crawler_path = os.path.abspath(script_path + "/config-crawler.nix")
stages_path = os.path.abspath(script_path + "/../stages")


def deploy():
    # for file, config in host_data:
    # get_hardware_configuration(host_name, host_config)
    return


def generate(path: Path, nixos_version="nixos-23.05"):
    # TODO: get nixos version for hive.nix
    # nixos_version = config["cluster"]["versions"]["nixos"]
    # nix_configs = [path for path in path.glob("*") if fnmatch(path.as_posix(), "*/[nN]ix[cC]onfigs")]
    nix_configs = list(path.glob("*[nN]ix[cC]onfigs"))
    if not nix_configs:
        print(f"No 'nixConfigs' folder found in '{path}'", file=sys.stderr)
        exit(1)
    nix_configs = nix_configs[0]
    host_data = [
        {"file": config, "config": get_host_information(config)}
        for config in get_nix_definitions(nix_configs)
    ]
    for data in host_data:
        folders = generate_folders(path, data)
        folders["iso"].write_text(generate_iso_nix(data))
        folders["mini_sys"].write_text(generate_mini_sys(path, data))
        # TODO: run nixfmt
    (path / "generated/hive.nix").write_text(
        generate_hive(path, nixos_version, host_data)
    )


def generate_iso_nix(host_data):
    return f"""# This is an auto generated file.
{{pkgs, lib, ... }}:
let
  machine-config =
    import ({crawler_path}) {{
      inherit pkgs lib;
      host-definition = "{host_data["file"]}";
    }};
in {{
  imports = [ {stages_path + "/0-iso.nix"} ];
  config = machine-config;
}}
"""


def generate_mini_sys(path, host_data, efi_boot=True):
    return f"""# This is an auto generated file.
    {{pkgs, lib, ... }}:
{{
  imports = [ 
    /etcd/nixos/{host_data["config"]["hostname"]}-mini-sys.nix
    /etcd/nixos/hardware-configuration.nix
    /etcd/nixos/modules
    ];
  hostname = "{{hostname}}";
  interface= "{{host.interface}}";
  ip = "{{host.ip}}";
  admin = {{
    hashedPwd = ''{host_data["config"]["admin"]["hashedPwd"]}'';
    name = "{host_data["config"]["admin"]["name"]}";
    sshKeys = [{host_data["config"]["admin"]["sshKeys"]}];
  }};
  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = config.services.openssh.ports;
  {"boot.loader.systemd-boot.enable = true; boot.loader.efi.canTouchEfiVariables = true;" if efi_boot else ""}
}}
"""


def generate_hive(path, nixos_version, host_data):
    hive_nix = f"""# This is an auto generated file.
{{
  meta.nixpkgs = import (
    builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/{nixos_version}.tar.gz"
  ){{}};
"""
    for data in host_data:
        hardware_configuration = generate_folders(path, data)["hardware_configuration"]
        hive_nix += f"""
    {data["config"]["hostname"]} = {{
        imports = [ 
        {data["file"]}
        {hardware_configuration}
        ];
    }};
}}"""
        return hive_nix


def generate_host_list(host_definitions):
    return None


# get all nix definitions from the directory
# returns all default.nix files from the first folder level
def get_nix_definitions(path):
    nix_files = list(Path(path).glob("*.nix"))  # list all nix files
    nix_files = [(path) for path in nix_files]  # make (filename, path) pairs
    folders = [(path) for path in Path(path).glob("*") if path.is_dir()]
    for folder in [path for path in folders if not (path / "default.nix").exists()]:
        print(
            f"Warning: no default.nix found in {folder}; ignoring folder.",
            file=sys.stderr,
        )
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
        "hardware_configuration": (
            generation_folder
            / definition_path_to_name(host_data["file"])
            / "hardware-configuration.nix"
        ),
    }


# returns the folder name from a path with a default nix or the nix file base name
def definition_path_to_name(path):
    path = Path(path)
    if path.is_dir():
        return path.name
    if path.is_file():
        return path.stem


def get_host_information(nix_definition_file):
    return nix_eval(crawler_path, args=[("host-definition", nix_definition_file)])


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


def get_hardware_configuration(hostname, host_config):
    if (
        os.system(
            f'scp {host_config["admin"]["name"]}@{host_config["deployment_target"]}:/etc/nixos/hardware-configuration.nix generated/{hostname}/hardware-configuration.nix'
        )
        != 0
    ):
        print(
            f"Warning: cannot receive hardware configuration for host {hostname}",
            file=sys.stderr,
        )


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


def main(path: Path = None):
    if path == None:
        path = Path().cwd()
    return generate(path)


if __name__ == "__main__":
    path = None
    if len(sys.argv) > 1:
        path = Path(sys.argv[1])
    main(path)
