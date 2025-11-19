
## Non Goals

- Configure Kubernetes and Container Apps
- Configure non-essential network like additional firewall rules
  - these can be added in the custom nix configs for the hosts
- Cluster Access from the internet
  - you should be able to extend the NixOS config for that purpose though
- Certificate management
  - optional scripts to generate certificates are part of the cluster module
  - you need to provide certificates on each machine but how they get there is up to you
  - in the examples the ``secret-service`` cluster module is used, however, this is a proof of concept implementation; use it at your own risk
- Updates (for now)
  - you decide when the cluster is ready for an update
  - you have to rotate certificates for your self
  - for now there is no process to change the kubernetes versions
    - this might change if a personal need arises

## Design Decisions
- Kubernetes services like etcd, kubelet, etc. are running directly on the machine and are not containers by themselves
- to achieve high availability, keepalived and haProxy are configured by default

## Default Values

- Certificates are linked to [best practices](https://kubernetes.io/docs/setup/best-practices/certificates/#certificate-paths)  paths at `/etc/kubernetes/pki/`
  - link source default paths are in `/var/lib/kubernetes/pki/` on the cluster machine

## Scripts
- create etcd certificates
  - certificates are security relevant, use the script at your own risk
  - run with ``nix run .#cluster.<clusterName>.kubernetes.createEtcdCertificates``
- create a Certificate Authority for kubernetes
  - ``nix run .#cluster.example.kubernetes.createK8sCA``
- create certificates for all configured kubernetes roles
  - ``.#cluster.example.kubernetes.createK8sCerts``
- create a service account for kubernetes
  - ``nix run .#cluster.example.kubernetes.createServiceAccount``
- create kube configs for administration
  - ``.#cluster.example.kubernetes.createKubeConfigs``
- TODO: script to generate all of the above at once

## Service Roles
- controlPlane: nodes running kubeservices (api-server, scheduler, controller manager, haProxy, keepalived) and etcd (if etcd role is not assigned).
- etcd: nodes there etcd is running. If empty, etcd will be deployed on all control plane nodes
- worker: nodes that can run workloads; can be combined with control-plane role

## Configuration Options
Documentation of the general relevant parameters to configure this cluster service

### Service Options
These are options that can and should be set in the service definition under `extraConfig`

**services.kubernetes.cluster.virtualIps**
- mandatory (if keepalived is not disabled)
- A list of ips under which the cluster is reachable.
- a list of ip addresses: `[ "1.2.3.4" ... ]`
- Used by keepalived
- one of the control plane nodes will be reachable by this IP
  - if the node fails, another node will backup the ip through a keepalivd failover

**services.kubernetes.cluster.certificates.generation**
- Options to fill general data for certificate generation
- certificate generation is optional, you can bring your own certificates
  - however, certificate generation already considers the kubernetes configuration -> no complex configuration required
- certificate generation is a clusterconfig script -> not part of the machine config
- options are defined in certificates.nix
  - current options (all string type): **organization**, **organizationUnit**, **country**, **province**, **locality**

#### nixOS options that can be reused in the service definition

**services.kubernetes.addonManager.addons**
- a set of addons for kubernetes
- used to define kubernetes resources that will be deployed on the cluster
- useful e.g. to deploy a gitops solution for cluster management

**services.keepalived.enable**
- enabled by default
- can be disabled to not use keepalived for high availability
- other keepalived config can be added to customize keepalived behavior
- WARNING: disabling keepalived is not tested

**services.haproxy.enable**
- enabled by default
- can be disabled to not use haProxy for high availability
- other haProxy config can be added to customize haProxy behavior
- WARNING: disabling haProxy is not tested

### Machine Annotations
These are annotations added to `domain.cluster.{clustername}.machines.{machinename}.annotations`.
They are machine level configurations needed by the cluster service module.
Side Note: using machine options does not work for cluster services options, because cluster service options are not known by machine configuration in the beginning of the cluster config evaluation.

**kubernetes.nodeLabels**
- optional
- attrs of strings: `{ label1 = "value1"; label2 = "value2"; ...}`
- these labels will be added to the node if this machines is registered by kubelet as node (by the addon manager).

**kubernetes.keepalived.virtualIpInterface**
- mandatory
- string: `"eth0"`
- the interface name used by keepalived
- if the node is a master node, this interface will be used for the virtual ip address

**kubernetes.keepalived.priority**
- optional
- int in the range of[255, 0]
- The keepalived priority of this control plane node; the node with the highest priority will first assume the virtual ip address
- 255 is the highest priority
- if the annotation is empty this node will be assigned automatically to an unused priority
  - automatic assignment starts with prio 255 (if unused)
  - assignment order is the order in which the control-plane role is assigned in the cluster service.

# High availability services
- (Red Hat tutorial loadbalancing)[https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/load_balancer_administration/index]
- HaProxy -> failover for software downtimes
- keepalived -> failover for hardware downtimes

# Kubernetes Addons
- addon manager is deployed on all control planes
- you can add kubernetes resources defined in nix to kubernetes with addon manager
- useful to setup a minimal usable cluster
- addon manager is used by the cluster service for basic configuration
  - e.g. node labels use the addon manager
  - if you disable the addon manager (or do not deploy certificates with sufficient rights for the addon manager) this basic configuration will fail or be skipped.