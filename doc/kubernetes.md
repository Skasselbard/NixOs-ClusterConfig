
## Non Goals

- Configure Kubernetes and Container Apps
- Configure non-essential network like additional firewall rules
  - these can be added in the custom nix configs for the hosts
- Cluster Access from the internet
  - you should be able to extend the NixOS config for that purpose though
- Automatic updates
  - you decide when the cluster is ready for an update

## Assumptions

There are some assumptions that are embedded in the project.
Some keep the configuration minimal and structured.
Others reflect personal taste.

The following assumptions may be of interest:

- K3s runs in containers on one or more host machines
- The K3s server is running in a [nixos-container](https://nixos.wiki/wiki/NixOS_Containers) (because it is an easy NixOS integration)
- The K3s agent runs in a podman container (because it needs to have privileged access, which I couldn't figure out for the nixos-containers)
- Each host can run at most one K3s server and/or agent
  - hosts can be defined without K3s containers for additional deployments
- Every K3s host and K3s container has a static IP address
  - non K3s hosts can be dynamic
- The network of K3s hosts is configured as macvlan
  - the host and the K3s containers share the same interface
- Containers are in the same subnet with the same gateway as the host
  - which of course should be reachable from the deploying machine
- The NixOS on the nested K3s server container (if it exists) has the same admin user as the host
- Kubernetes versions are shared
  - All K3s-servers run the same NixOs version
  - All K3s-agents run the same Kubernetes image