#!/bin/python3
import os
import argparse
from pathlib import Path
import configuration

py_script_path = os.path.abspath(os.path.dirname(__file__))


def build_host(args, nixos_version="nixos-23.05"):
    # acquire sudo if needed
    os.system('sudo echo ""') if not args.dry and args.device else None
    name = args.name
    configuration.generate(Path.cwd(), nixos_version, not args.mbr_boot)
    if not args.dry:
        # cmds
        generate_iso = f"nixos-generate --format iso --configuration generated/{name}/iso.nix -o generated/{name}/iso -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/{nixos_version}.tar.gz"
        copy_to_medium = f"sudo dd if=generated/{name}/iso/iso/nixos.iso of={args.device} bs=4M conv=fsync status=progress"

        if os.system(generate_iso) == 0:
            if args.device != None:
                # if the iso build was successful and should be copied to a device: start copying
                os.system(copy_to_medium)
            else:
                return
        else:
            exit(1)


def get_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        # TODO: update parser
        description="Build a nix iso configuration with the network config of the given machine. Generates an iso file in $PWD/generated/$hostname/$hostname.iso"
    )
    parser.add_argument(
        "-d",
        "--device",
        help="The output device where the created iso image should be copied to to make a bootable device.",
    )
    parser.add_argument(
        "-n",
        "--name",
        required=True,
        help="Name of the machine to prepare. The name will be the stem of your nix definition in the nixConfigs folder (e.g. 'machine' for 'machine.nix') or the folder name for definitions in a folder.",
    )
    parser.add_argument(
        "-e",
        "--mbr-boot",
        help="If this flag is set the installation iso is built for MBR legacy systems instead of efi systems (see nixos manual)",
        action="store_true",
    )
    parser.add_argument(
        "--dry",
        help="Make a dry run of the generation without generating an iso image",
        action="store_true",
    )
    return parser


if __name__ == "__main__":
    build_host(get_parser().parse_args())
