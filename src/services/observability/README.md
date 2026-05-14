# Observability Cluster Service

## Overview

This document describes the planned architecture for a built-in `observability` cluster service for `NixOs-Staged-Hive`.
The first target is a practical home-lab and small-cluster stack built around:

- **Grafana** for dashboards and exploration
- **Prometheus** for metrics collection and rules
- **Loki** for logs
- **Promtail** for log shipping from `systemd-journald`
- **Node exporter** on every selected machine for host metrics

The design follows the current cluster service model from [`doc/ClusterServices.md`](../../../doc/ClusterServices.md):

- the service is defined once at cluster scope
- selectors determine which machines participate
- roles determine which machines host the central components
- machine-specific behavior is derived from resolved role membership through `config.clusterConfig`

The initial design intentionally prefers **low operational complexity** over high availability.
By default, metrics and logs are available from every selected machine, while central storage remains **ephemeral** unless explicitly enabled later.

---

## Goals

- Provide **common node observability** for every selected machine.
- Provide a **single built-in stack** for metrics, logs, and dashboards.
- Make the stack **fully customizable** while still offering an opinionated default profile.
- Use **`systemd` journal logs as the default log source**.
- Default to **ephemeral storage** so the first version stays easy to deploy and recover.
- Fit naturally into the existing cluster service pipeline and role model.

## Non Goals

- Full multi-node HA for Prometheus, Loki, or Grafana in the first version.
- Long-term durable retention by default.
- Automatic instrumentation of every possible service.
- Distributed object storage or multi-binary Loki microservices mode.
- Auto-discovery magic that hides configuration details from users.

---

## Best-Practice Research Summary

This architecture is based on current upstream guidance and adapted for a small NixOS cluster.

### Prometheus

Relevant upstream guidance:

- [Prometheus instrumentation best practices](https://prometheus.io/docs/practices/instrumentation/)
- [Prometheus metric and label naming](https://prometheus.io/docs/practices/naming/)

Important takeaways applied here:

- Prefer **low-cardinality labels** and avoid labels with user IDs, request IDs, or other unbounded values.
- Prefer **base units** and standard naming like `_seconds`, `_bytes`, `_total`.
- Track common service signals: **requests, errors, latency, in-progress work**.
- Export **timestamps instead of “time since” gauges** when tracking latest success or last processing time.
- Start with **few labels and few scrape jobs**, then add more only for real use cases.

### Loki

Relevant upstream guidance:

- [Loki label best practices](https://grafana.com/docs/loki/latest/get-started/labels/bp-labels/)
- [Loki sizing guidance](https://grafana.com/docs/loki/latest/setup/size/)

Important takeaways applied here:

- Use **static labels** such as `cluster`, `host`, `service`, `environment`, `role`.
- Use **dynamic labels sparingly** to avoid stream explosion and index growth.
- Do **not** label on request IDs, session IDs, trace IDs, or arbitrary per-event values.
- For a small cluster, keep Loki in a **simple single-binary mode** first; distributed mode adds operational cost that is not justified initially.
- Default storage should be **ephemeral** for simplicity, with persistence as an explicit opt-in mode.

### Grafana

Relevant upstream guidance:

- [Grafana provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)

Important takeaways applied here:

- Provision **data sources and dashboards from files** so configuration stays version-controlled and reproducible.
- Provisioned dashboards should be treated as **generated or source-controlled assets**, not edited permanently in the UI.
- Use stable **UIDs** for provisioned dashboards and data sources.
- Keep secrets out of dashboard JSON and use **environment variables / secure configuration paths** where needed.

---

## High-Level Architecture

The observability service is split into two kinds of functionality:

1. **Per-node agents**
   - run on every selected machine
   - expose metrics
   - ship logs from `journald`

2. **Central services**
   - receive metrics and logs
   - provide dashboards and queries
   - optionally store short-lived or persistent history

### Default Data Flow

```text
[selected machines]
  ├─ node_exporter ----------------------> Prometheus
  ├─ service metrics endpoints ---------> Prometheus
  └─ promtail -> journald -------------> Loki

Grafana -------------------------------> Prometheus
Grafana -------------------------------> Loki
```

### Default Topology

The default deployment should support one central machine that hosts the stack:

- **Grafana** on a `dashboard` role machine
- **Prometheus** on a `metrics` role machine
- **Loki** on a `logs` role machine

For the smallest setup, all three roles may point to the **same machine**.
This should be the default recommendation.

---

## Roles

The service should use responsibility-based roles instead of product-only roles.
This keeps the API flexible even if internals change later.

### `dashboard`

Machines in this role run Grafana.

Responsibilities:

- provision data sources for Prometheus and Loki
- provision starter dashboards
- expose the main UI for operators

### `metrics`

Machines in this role run Prometheus.

Responsibilities:

- scrape node exporters on all selected machines
- scrape user-defined service metrics endpoints
- optionally load rules and recording rules

### `logs`

Machines in this role run Loki.

Responsibilities:

- ingest logs from promtail agents
- serve log queries to Grafana
- optionally retain short-lived or persistent logs depending on storage mode

### `storage` (optional)

This role is **not required** in the initial version, but the design should leave room for it.

Use cases:

- explicit persistent storage placement
- future split between compute roles and data roles
- future distributed backend or object-store based storage

In v1, if `storageMode = "ephemeral"`, this role can be omitted entirely.

---

## Node-Level Components

Every selected machine should be able to participate in observability, independent of whether it hosts central services.

### Metrics on Every Node

Default behavior:

- enable `services.prometheus.exporters.node`
- expose metrics on a configurable port
- open access only where required by the cluster design
- add stable labels in Prometheus relabeling such as:
  - `cluster`
  - `hostname`
  - `role` when meaningful

Optional future additions:

- process exporters for selected services
- nginx / postgres / smartctl / systemd exporters when explicitly enabled
- custom scrape targets defined by service owners

### Logs on Every Node

Default behavior:

- enable `promtail`
- read from **`systemd-journald`** rather than assuming file-based logs
- forward to Loki
- keep labels bounded and boring

Recommended default labels for logs:

- `cluster`
- `host`
- `job`
- `service` or `unit` when bounded
- `environment` if provided globally

Labels that should **not** be defaults:

- request IDs
- trace IDs
- user IDs
- container hashes
- arbitrary command arguments

This aligns with Loki guidance to keep stream cardinality low.

---

## Storage Model

### Default: `ephemeral`

The default storage mode should be `ephemeral`.

Implications:

- Prometheus TSDB state is not expected to survive machine rebuilds or role restarts.
- Loki data is not expected to survive rebuilds or role restarts.
- Grafana provisioning comes from files, so dashboards and data source definitions are reproducible even if local state is lost.
- The stack is treated as an **operational convenience layer**, not the source of record.

This is the recommended first mode because it:

- keeps initial setup simple
- avoids forcing the user to decide on storage architecture immediately
- avoids premature coupling to local disks or distributed storage backends

### Optional: `local`

A later mode can enable local persistence on the machine hosting `metrics` and `logs`.

Implications:

- one machine stores Prometheus and/or Loki state
- if that machine is offline, historical data is unavailable
- recovery is simple, but this is not highly available

This is the simplest persistence option when users want short retention without distributed storage.

### Future: `distributed`

This mode should be reserved for later and not implemented by default.

Potential future meaning:

- remote object storage for Loki
- a metrics backend beyond single-node Prometheus
- replicated storage or remote write architecture

For the target scale of this repository, this would likely be overkill at first.

---

## Configuration Model

The service should support two layers of configuration.

### 1. Opinionated Default Profile

A profile such as `profiles.default.enable = true` should provide a ready-to-use setup:

- node exporter on all selected machines
- promtail reading journald on all selected machines
- Prometheus scraping node exporters
- optional starter scrape jobs for explicitly enabled service exporters
- Grafana provisioning with:
  - Prometheus data source
  - Loki data source
  - starter dashboards for node health, CPU, memory, disk, network, and service logs

This gives users a working stack quickly.

### 2. Fully Custom Layer

All core components must remain directly configurable.

Suggested escape hatches:

- `services.observability.prometheus.extraScrapeConfigs`
- `services.observability.prometheus.rules`
- `services.observability.prometheus.extraConfig`
- `services.observability.loki.extraConfig`
- `services.observability.promtail.extraConfig`
- `services.observability.grafana.provisioning.datasources`
- `services.observability.grafana.provisioning.dashboards`
- `services.observability.grafana.extraConfig`

The opinionated profile should **compose into** this raw layer rather than bypassing it.

---

## Recommended Service API Shape

The exact names can change during implementation, but the architecture assumes a shape similar to this:

```nix
services.observability = {
  selectors = [ filters.clusterMachines ];

  roles = {
    dashboard = [ (filters.hostname "monitor") ];
    metrics = [ (filters.hostname "monitor") ];
    logs = [ (filters.hostname "monitor") ];
  };

  storageMode = "ephemeral";

  profiles.default.enable = true;

  metrics = {
    nodeExporter.enable = true;
    scrapeInterval = "30s";
    extraScrapeConfigs = [ ];
  };

  logs = {
    journald.enable = true;
    labels = {
      cluster = "lab";
      environment = "home";
    };
  };

  grafana = {
    enable = true;
    provisioning = { };
  };
};
```

Key design choices:

- **selectors** define where agents run
- **roles** define where central services run
- **storageMode** controls persistence behavior without forcing a separate storage topology
- **profiles.default** can be enabled or disabled without losing access to raw config

---

## Metrics Design

### Default Scrape Targets

The default profile should scrape:

- node exporter on all selected nodes
- Prometheus self-metrics
- Loki self-metrics
- Grafana self-metrics where available

### Service Metrics

Service metrics should be **explicitly configurable** rather than fully automatic.
This keeps the system understandable and avoids surprising scrape failures.

Recommended pattern:

- built-in defaults only for core observability components
- user-provided scrape targets for application services
- later extension points for common NixOS services

### Naming and Labels

The documentation for application owners should encourage:

- metric names with base units like `_seconds`, `_bytes`, `_total`
- low-cardinality labels
- counters for event counts and failures
- gauges for current state
- histograms for latency where percentile-like analysis is desired

---

## Logging Design

### Why Journald First

Using `journald` first is a strong fit for NixOS because:

- many system services already log there
- it avoids file path assumptions across machines
- it covers systemd-managed services consistently
- it reduces custom per-service log plumbing

### Promtail Pipeline

Promtail should initially:

- read systemd journal entries
- attach a bounded base label set
- optionally relabel `systemd_unit` into a friendly bounded label when useful
- avoid parsing every field into labels

### Query Strategy

The design should prefer:

- broad static labels for stream selection
- text filters and parsers at query time for more detailed analysis

This follows Loki guidance and keeps ingestion cheaper and safer.

---

## Grafana Design

Grafana should be configured entirely through provisioning files generated by the service.

### Provisioned Datasources

The service should provision at least:

- one Prometheus data source
- one Loki data source

Best practices to follow:

- assign stable UIDs
- use `editable = false` by default for generated data sources
- keep URLs derived from resolved cluster roles
- reserve secrets for secure config paths or environment-based injection

### Provisioned Dashboards

The service should ship a starter dashboard set, for example:

- **Cluster Overview**
- **Node Health**
- **Node CPU / Memory / Disk / Network**
- **Logs by Host / Unit**
- **Observability Stack Health**

Dashboards should:

- be file-provisioned
- use stable UIDs
- be considered source-controlled assets
- avoid local-only UI edits as a workflow

---

## Failure Modes and Trade-Offs

### If the `metrics` Machine Is Offline

- no new scrapes occur
- historical metrics in `ephemeral` mode may be lost on restart
- nodes continue exposing metrics locally

### If the `logs` Machine Is Offline

- promtail cannot deliver new logs to Loki
- depending on promtail buffering behavior, some logs may be retried but durable guarantees should not be assumed in `ephemeral` mode
- journals remain on the source machines according to local journal retention

### If the `dashboard` Machine Is Offline

- data collection may still continue if Prometheus and Loki are separate
- dashboards and exploration are unavailable

### If One Machine Runs All Roles

This is the preferred v1 topology for simplicity, but it means:

- one node failure removes the whole central observability UI/query plane
- agents on other nodes still produce logs and metrics locally
- rebuild and recovery are straightforward because the configuration remains declarative

---

## Security and Network Posture

The service should keep the default network posture conservative.

Recommended defaults:

- exporters should bind only as broadly as needed for central scraping
- Grafana should not be Internet-exposed by default
- central ports should be opened only for cluster-internal traffic
- future authentication and TLS hooks should be possible without redesigning the service API

Out of scope for v1:

- public ingress
- SSO
- multi-tenant Grafana administration model

---

## Implementation Phases

### Phase 1: Minimal Useful Stack

- one `observability` cluster service
- node exporter on selected nodes
- promtail on selected nodes reading journald
- single Prometheus instance
- single Loki instance
- single Grafana instance
- ephemeral storage by default
- starter dashboards and data sources provisioned automatically

### Phase 2: Better Customization

- richer exporter toggles
- custom scrape target helpers
- optional recording rules and alerts
- user-provided dashboards merged with built-ins

### Phase 3: Persistence Options

- `local` storage mode
- explicit storage paths and retention settings
- optional separation between compute and storage roles

### Phase 4: Advanced Scale Patterns

- remote backends or distributed storage
- more advanced HA role layouts
- optional alert routing integrations

---

## Recommendation

For this repository, the best first implementation is:

- **every selected node** runs node exporter and promtail
- **systemd journal** is the default log source
- **ephemeral** is the default storage mode
- **one machine can host `dashboard`, `metrics`, and `logs` together**
- a **default profile** gives immediate value
- users retain **full raw configuration control** for Prometheus, Loki, and Grafana

This keeps the new cluster service aligned with the project’s declarative philosophy while avoiding unnecessary early complexity.

---

## Open Questions for Implementation

1. Should `dashboard`, `metrics`, and `logs` each require **exactly one** role member in v1, or should empty roles simply disable that subsystem?
2. Should the first version ship only **node-level dashboards**, or also include dashboards for the observability stack itself?
3. Should `local` persistence later reuse the same role machines, or introduce an explicit `storage` role at that point?
