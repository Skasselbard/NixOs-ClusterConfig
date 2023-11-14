import argparse
import os
import subprocess
import pathlib
import sys

# subcommands
from configuration import generate as get_config
import installer


def main():
    parser = argparse.ArgumentParser(
        description="Setup a K3s cluster from a set of plans.", prog="K3s-Cluster"
    )
    parser.add_argument(
        "-p",
        "--path",
        help="The root directory to search for the necessary files.",
        default=pathlib.Path.cwd(),
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
        description="Creates the folder and file structure expected by the scripts with sample files",
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
    root_dir = pathlib.Path(args.path)
    os.chdir(root_dir)
    configuration = None if args.subcommand == "setup" else get_config(args.path)
    if args.subcommand == "install":
        install_args = parse_subargs(install_parser)
        installer.build_host(install_args, yaml.safe_load(configuration))
    elif args.subcommand == "configuration":
        _config_args = parse_subargs(config_parser)
        print(configuration)
    elif args.subcommand == "setup":
        _setup_args = parse_subargs(setup_parser)
        init_dir(pathlib.Path(args.path))
    elif args.subcommand == "hive":
        hive_nix = root_dir / "generated/hive.nix"
        if args.hive_commands == "generate":
            _generate_args = parse_subargs(generate_parser)
            hive_nix.write_text(hive.get_hive_nix(yaml.safe_load(configuration)))
        elif args.hive_commands == "build":
            if not args.skip_generate:
                hive_nix.write_text(hive.get_hive_nix(yaml.safe_load(configuration)))
            _, colmena_args = parse_known_subargs(build_parser)
            colmena("build", hive_nix, colmena_args)
        elif args.hive_commands == "deploy":
            if not args.skip_generate:
                hive_nix.write_text(hive.get_hive_nix(yaml.safe_load(configuration)))
            _, colmena_args = parse_known_subargs(deploy_parser)
            colmena("apply", hive_nix, colmena_args)
        else:
            print(hive.get_hive_nix(yaml.safe_load(configuration)))
    else:
        # case should already be caught by argparse
        print("Unrecognized subcommand", file=sys.stderr)


def colmena(subcommand, hive_nix: pathlib.Path, args):
    cmd = " ".join(["colmena", subcommand, "-f", str(hive_nix)] + args)
    print(f"Running '{cmd}'")
    os.system(cmd)


def parse_subargs(parser: argparse.ArgumentParser):
    # get the command name from the program name, and parse all arguments after the occurrence of this command
    return parser.parse_args(sys.argv[sys.argv.index(parser.prog.split()[-1]) + 1 :])


def parse_known_subargs(parser: argparse.ArgumentParser):
    # get the command name from the program name, and parse all arguments after the occurrence of this command
    return parser.parse_known_args(
        sys.argv[sys.argv.index(parser.prog.split()[-1]) + 1 :]
    )


# TODO: update examples
def init_dir(root_path: pathlib.Path):
    plans = root_path / "plans"
    if not plans.exists():
        plans.mkdir(parents=True, exist_ok=True)
        (plans / "hosts.csv").open("w").writelines(
            [
                "name, interface, ip, admin\n",
                "olaf, eno3, 192.168.100.5, admin\n",
                "rolf, enps1, 192.168.100.6, admin\n",
            ]
        )
        (plans / "k3s.csv").open("w").writelines(
            [
                "host, name, type, ip\n",
                "olaf, olaf-server, init, 192.168.100.10\n"
                "olaf, olaf-agent, agent, 192.168.100.11\n"
                "rolf, olaf-agent, server, 192.168.100.12\n",
            ]
        )
        (plans / "network.yaml").open("w").writelines(
            ['netmask: "24"\n', "gateway: 192.168.100.1\n"]
        )
    (root_path / "nixConfigs").mkdir(parents=True, exist_ok=True)
    (root_path / "secrets").mkdir(parents=True, exist_ok=True)
    (root_path / "manifests").mkdir(parents=True, exist_ok=True)
    (root_path / "partitioning").mkdir(parents=True, exist_ok=True)
    (root_path / "generated").mkdir(parents=True, exist_ok=True)


if __name__ == "__main__":
    main()
