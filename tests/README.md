# Testing

Run the evaluation regression suite with Nix flakes enabled:

```sh
nix flake check
```

The `checks.x86_64-linux.evaluation` check evaluates structural validation, naming, cross-cluster VM hosting, guest service and user isolation, package scopes, deployment command arguments, and the deployment-host package system. It does not deploy machines or format disks. `nix flake check --no-build` evaluates the checks without building the small success derivation.

To catch evaluation warnings as errors when running the suite, use:

```sh
nix flake check --no-build --option abort-on-warn true
```

This is stricter than checking for a particular warning and can also fail on
unrelated evaluation warnings from inputs.

During local development, Git flakes only include tracked files. Add new files to the Git index before using the Git flake, or evaluate the working tree explicitly:

```sh
nix build --no-link --impure --expr '(builtins.getFlake "path:/path/to/NixOs-Cluster-Config").checks.x86_64-linux.evaluation'
```

Run `tests/benchmark.sh` for a repeatable cold-process evaluation benchmark. It prints elapsed time and Nix evaluator statistics, does not build systems, and disables the flake evaluation cache. Compare the same machine, Nix version and inputs.

The example flakes use the local project as an input. If their lock files are stale, refresh only that input with `nix flake update clusterConfigFlake --flake ./examples/01-simpleCluster` (substitute the relevant example). When testing an unstaged working tree, use `--override-input clusterConfigFlake path:/absolute/path/to/NixOs-Cluster-Config` and `--no-write-lock-file`.

Live integration tests are separate: `examples/01-simpleCluster/test.sh` and `examples/04-secretDeployment/test.sh` require deployed VMs. The secret example's `test-helpers.sh` modifies example secret state; read its documentation before running it.