import argparse
import os
import subprocess
from pathlib import Path
import sys

# subcommands
from configuration import generate
import installer


def main():
    parser = argparse.ArgumentParser(
        description="Setup a Colmena hive from a set of nix configs.",
        prog="NixOs-Staged-Hive",
    )
    parser.add_argument(
        "-p",
        "--path",
        help="The root directory to search for the necessary files.",
        default=Path.cwd(),
    )
    parser.add_argument(
        "-v",
        "--nixos-version",
        help="The nixos version that should be used",
        default="nixos-23.05",
    )
    subparsers = parser.add_subparsers(
        dest="subcommand",
        required=True,
    )
    install_parser = subparsers.add_parser(
        name="install",
        parents=[installer.get_parser()],
        add_help=False,
        description=installer.get_parser().description,
    )
    setup_parser = subparsers.add_parser(
        name="setup",
        description="Creates the folder and file structure expected by the scripts",
    )
    hive_parser = subparsers.add_parser(
        name="hive",
        description="Used to generate, build and deploy the hive configuration files. Building and deploying is done by calling colmena with the given arguments.",
    )
    hive_subparsers = hive_parser.add_subparsers(
        dest="hive_commands",
    )
    hive_parser.add_argument(
        "-s",
        "--skip-generate",
        help="skips the automatic regeneration of the hive.nix",
        action="store_true",
    )
    generate_parser = hive_subparsers.add_parser(
        name="generate",
        description="Generates the configuration files used later by colmena to deploy. The results are written to files in $PWD/generate",
    )
    build_parser = hive_subparsers.add_parser(
        name="build",
        description="Forwards the given arguments to colmena build.",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog=subprocess.run(
            "colmena build --help".split(),
            capture_output=True,
            text=True,
        ).stdout,
    )
    deploy_parser = hive_subparsers.add_parser(
        name="deploy",
        description="Forwards the given arguments to colmena apply.",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog=subprocess.run(
            "colmena apply --help".split(), capture_output=True, text=True
        ).stdout,
    )

    args, _ = parser.parse_known_args()
    root_dir = Path(args.path)
    nixos_version = args.nixos_version
    os.chdir(root_dir)
    os.environ["HIVE_ROOT"] = root_dir.absolute().as_posix()

    if args.subcommand == "install":
        install_args = parse_sub_args(install_parser)
        installer.build_host(install_args, nixos_version)
    elif args.subcommand == "setup":
        _setup_args = parse_sub_args(setup_parser)
        init_dir(root_dir)
    elif args.subcommand == "hive":
        hive_nix = root_dir / "generated/hive.nix"
        if args.hive_commands == "generate":
            _generate_args = parse_sub_args(generate_parser)
            generate(root_dir, nixos_version)
        elif args.hive_commands == "build":
            if not args.skip_generate:
                generate(root_dir, nixos_version, query_hardware_config=True)
            _, colmena_args = parse_known_sub_args(build_parser)
            colmena("build", hive_nix, colmena_args)
        elif args.hive_commands == "deploy":
            if not args.skip_generate:
                generate(root_dir, nixos_version, query_hardware_config=True)
            _, colmena_args = parse_known_sub_args(deploy_parser)
            colmena("apply", hive_nix, colmena_args)
        else:
            print(hive_parser.usage)
    else:
        # case should already be caught by argparse
        print("Unrecognized subcommand", file=sys.stderr)


def colmena(subcommand, hive_nix: Path, args):
    cmd = " ".join(["colmena", subcommand, "-f", str(hive_nix)] + args)
    print(f"Running '{cmd}'")
    os.system(cmd)


def parse_sub_args(parser: argparse.ArgumentParser):
    # get the command name from the program name, and parse all arguments after the occurrence of this command
    return parser.parse_args(sys.argv[sys.argv.index(parser.prog.split()[-1]) + 1 :])


def parse_known_sub_args(parser: argparse.ArgumentParser):
    # get the command name from the program name, and parse all arguments after the occurrence of this command
    return parser.parse_known_args(
        sys.argv[sys.argv.index(parser.prog.split()[-1]) + 1 :]
    )


def init_dir(root_path: Path):
    (root_path / "nixConfigs").mkdir(parents=True, exist_ok=True)
    (root_path / "manifests").mkdir(parents=True, exist_ok=True)
    (root_path / "generated").mkdir(parents=True, exist_ok=True)


if __name__ == "__main__":
    main()
