## Machine Commands

- ``nix build .#machines.<machine name>.iso``: build an iso file for the machine
- ``nix run .#machines.<machine name>.<command>``
- ``nix run .#machines.<machine name>.build``: run a nix build of the machine with nixos-rebuild
- ``nix run .#machines.<machine name>.deploy``: deploy the machine to the deployment.target with nixos-rebuild
- ``nix run .#machines.<machine name>.connect``: connect to the deployment.target via ssh
- ``nix run .#machines.<machine name>.hardware-configuration``: connect to the deployment.target and print the hardware configuration.nix via ssh

### Service Commands
- ``nix run .#machines.<machine name>.services.<service name>.start``: 1
- ``nix run .#machines.<machine name>.services.<service name>.restart``: deploy the machine to the deployment.target
- ``nix run .#machines.<machine name>.services.<service name>.stop``: connect to the deployment.target via ssh
- ``nix run .#machines.<machine name>.services.<service name>.status``: connect to the deployment.target and print the hardware configuration.nix via ssh
- ``nix run .#machines.<machine name>.services.<service name>.log``: connect to the deployment.target and print the service log via ssh

### Nixos Anywhere Commands
- ``nix run .#machines.<machine name>.create``: Redeploys the entire nixos system on the deployment.target
- ``nix run .#machines.<machine name>.format``: Runs the configured format script on deployment.target

### Secret Service Commands
- ``nix run .#machines.<machine name>.deploy``: a normal deployment is needed to update the service itself
- ``nix run .#machines.<machine name>.deploySecrets``: deploy the secrets defined for the secret-service to the deployment.target