# Cheat Sheet

Quick reference for common ClusterConfig commands. See the [Command Reference](CommandReference.md) for detailed descriptions.

## Machine Commands

```bash
# Build
nix build .#<cluster>.<machine>.iso                   # Build installation ISO
nix run .#<cluster>.<machine>.build                    # Build system locally

# Deploy
nix run .#<cluster>.<machine>.create                   # Initial install (nixos-anywhere)
nix run .#<cluster>.<machine>.deploy                   # Update system (nixos-rebuild)

# Utilities
nix run .#<cluster>.<machine>.connect                  # SSH into machine
nix run .#<cluster>.<machine>.hardware-configuration   # Print hardware config
nix run .#<cluster>.<machine>.format                   # Run format script remotely
```

## Fleet Deployment (Colmena)

```bash
nix run .#colmena apply                                # Deploy all machines
nix run .#colmena apply -- --on <machine>              # Deploy one machine
nix run .#colmena build                                # Build without deploying
```

## Secret Deployment

```bash
nix run .#<cluster>.<machine>.deploySecrets            # Deploy encrypted secrets
```