
## Non Goals

- Configure Kubernetes and Container Apps
- Configure non-essential network like additional firewall rules
  - these can be added in the custom nix configs for the hosts
- Cluster Access from the internet
  - you should be able to extend the NixOS config for that purpose though
- Certificate management
  - you need to provide them on the machine but how they get there is up to you
- Updates (for now)
  - you decide when the cluster is ready for an update
  - you have to rotate certificates for your self
  - for now there is no process to change the kubernetes versions
    - this might change if a personal need arises

## Design Decisions
- Kubernetes services like etcd, kubelet, etc. are running directly on the machine and are not containers by themselves

## Default Values

- Certificates are linked to [best practices](https://kubernetes.io/docs/setup/best-practices/certificates/#certificate-paths)  paths at `/etc/kubernetes/pki/`
  - link source default paths are in `/var/lib/kubernetes/pki/` on the cluster machine

## Scripts
- create etcd certificates
  - certificates are security relevant, use the script at your own risk
  - run with ``nix run .#cluster.<clusterName>.kubernetes.createEtcdCertificates``