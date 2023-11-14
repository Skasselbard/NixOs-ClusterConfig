#!/bin/python3
import os
import sys
import subprocess
from pathlib import Path
import json


script_path = os.path.abspath(os.path.dirname(__file__))
crawler_path = os.path.abspath(script_path + "/config-crawler.nix")
stages_path = os.path.abspath(script_path + "/../stages")


def generate(path):
    # TODO: get nixos version for hive.nix
    # nixos_version = config["cluster"]["versions"]["nixos"]
    host_definitions = get_nix_definitions(path)
    for definition in host_definitions:
        print(get_host_information(definition))



def generate_stage_zero_nix(definition):
    return f"""# This is an auto generated file.
{{pkgs, lib, ... }}:
let
  machine-config =
    import ({crawler_path}) {{
      inherit pkgs lib;
      host-definition = "{definition}";
    }};
in {{
  imports = [ {stages_path + "/0-iso.nix"} ];
  config = {{}} // machine-config;
}}
"""

def generate_stage_three_nix(definition):
    return f"""# This is an auto generated file.
{{
  meta.nixpkgs = import (
    builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/{nixos_version}.tar.gz"
  ){{}};
}}"""
    for host_name, host_config in config["cluster"]["hosts"].items():
        (Path.cwd() / f"generated/{host_name}").mkdir(parents=True, exist_ok=True)
        get_hardware_configuration(host_name, host_config)
        nix_config += (
            f"{host_name} = "
            + populate_host(host_name, host_config, config["cluster"], is_hive=True)
            + ";\n"
        )

# get all nix definitions from the directory
# returns all default.nix files from the first folder level
def get_nix_definitions(path):
    nix_files = list(Path(path).glob("*.nix"))
    folders = [path for path in Path(path).glob("*") if path.is_dir()]
    for folder in [path for path in folders if not (path / "default.nix").exists()]:
        print(
            f"Warning: no default.nix found in {folder}; ignoring folder.",
            file=sys.stderr,
        )
    return nix_files + [
        path / "default.nix" for path in folders if (path / "default.nix").exists()
    ]


def get_host_information(nix_definition_file):
    return nix_eval(crawler_path, "config", [("host-definition", nix_definition_file)])


def nix_eval(path, attribute, args):
    args = " ".join(
        [f"--argstr {name} {value}" for (name, value) in args]
    )  # format arguments
    result = subprocess.run(
        f"nix-instantiate --eval --strict --json {path} {args} -A {attribute}".split(),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Error evaluating {path}: {result.stderr}", file=sys.stderr)
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


def get_ssh_keys(hostname: str):
    keys = []
    keys.extend(secrets_dir.glob("*all*.pub"))
    keys.extend(secrets_dir.glob("*All*.pub"))
    keys.extend(secrets_dir.glob("*ALL*.pub"))
    keys.extend(secrets_dir.glob(f"*{hostname}*.pub"))
    if len(keys) == 0:
        print(f"Warning: no ssh keys found for host {hostname}", file=sys.stderr)
    return [f"{key.read_text()}" for key in keys]


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
    print(main(path))
