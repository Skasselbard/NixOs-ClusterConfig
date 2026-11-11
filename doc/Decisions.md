# Decisions

This document records design decisions that are not obvious from the code, in particular decisions *against* a feature, so that they are not re-litigated every few months.

## D1: Service-level tags are not supported

**Decision:** services are not tagged. Node tags and labels exist, service definitions do not.

**Context:** tags on nodes answer "which nodes are part of this group", which is the selection direction ClusterConfig uses everywhere: a service declares `selectors`/`roles`, and the pipeline resolves those filters to nodes. Extending tags to services suggests the inverse query ("which services run on / relate to this node or this other service"), and that was considered and rejected.

**Reasoning:**

- **Evaluation order.** `node.services` is produced by the service selection transformation. A `filters.tagsAny "service:vault"` would have to read `node.services` while `node.services` is being computed. Selection and reverse-selection cannot both exist without a fixed point in the pipeline.
- **No independent consumer.** A service that needs the nodes of another service declares its own `selectors` with the same filter vocabulary. A service that needs another service's *metadata* reads its declared options. Both already work and neither needs a registry.
- **Coupling.** Services are independent modules with `definition` and `extraConfig` closures. Cross-service tag queries introduce a dependency graph that the design deliberately avoids.
- **Dead vocabulary.** A tag nobody reads looks like an API while silently matching the empty set. Because there is no concrete consumer, the vocabulary would rot.

**Consequences:**

- If a real capability-contract use case appears (for example "every service tagged `stateful` must have a backup provider", or an observability module collecting scrape targets from providers), it is an additive change: a `tags` option in the service definition type, plus a consumer that reads it. Nothing in the current design blocks that.
- Until then, the cheapest way to attach meaning to a service is an option declared under `extensions.clusterServices.<name>.options`.

## D2: Tags and labels are declared, not derived

**Decision:** `tags` and `labels` hold exactly what the cluster definition declares. ClusterConfig does not derive tags such as `type:vm`, `system:x86_64-linux`, `backend:microvm` or `vm-host:host-a`, and there is no tag module computing them.

**Context:** default tags for facts that are already options were considered, so that a `filters.tagsAny "vm"` could replace a `filters.nodeOption [ … ]` query.

**Reasoning:**

- Every such fact is already a declared option, and the generic `filters.nodeOption` can query it without a second vocabulary that could drift from the option it mirrors.
- Derived tags need a stage at which they can be computed. Declared facts and evaluated facts (`system.nixos.release`, service-added settings) live in different pipeline stages, so the same tag prefix would have worked in some stages and not in others — the kind of asymmetry that produces silently empty selections.
- A derivation layer plus a module for configuring it is more machinery than the problem justifies.

**Consequences:** selecting on a fact that is an option uses `filters.nodeOption` (or `clusterMachines`/`clusterVms` for the node type). Tags are reserved for classification that no option encodes, such as `prod`, `gpu`, `tenant-a` or `public`.

## D3: Selectors may query the first-pass machine configuration

**Decision:** service selection runs as an internal pipeline step *after* the first node evaluation, so `service.selectors` and `roles` can use `filters.machineOption` to match evaluated NixOS options. The step is not exposed as a transformation hook, and no additional `evalMachines` round was added.

**Context:** node `nixosConfiguration`s only exist after the first evaluation, but service selection used to run before it (as a `clusterTransformation`). That made every evaluated fact — release, kernel, anything a node's own modules set — invisible to selectors, even though declared options are one `filters.nodeOption` query away.

**Reasoning:**

- The restriction came from the *registration* of the selection step as a cluster transformation, not from a property of the pipeline. Moving the step one stage later removes it without extra evaluation work.
- An additional `evalMachines` round, or a second per-node attribute (`earlyNixosConfiguration`), was rejected: both add a full module-system evaluation round or a second source of truth for the same data, and the existing `nixosConfiguration` attribute is already written more than once by design.
- Not a transformation hook: the ordering relative to the node evaluation is part of the pipeline contract. Exposing it would let modules move selection around and silently change what selectors can see.
- Selector validation had to move with it (it resolves the same filters), so an invalid selector is now reported after the first node evaluation instead of before it. The error messages are unchanged.

**Consequences:**

- `machineOption` reads the **initial** configuration. Options that are only added later — by service modules, or by the `clusterConfig` injected for the final evaluation — are not visible to selectors. This is inherent to the staged build: a service cannot select nodes based on its own effects.
- `clusterTransformations` no longer populate `node.services`; `moduleTransformations` do. See [Extensions](Extensions.md#4-transformations-extensionstransformations).
- Prefer `filters.nodeOption` for declared data: it has no stage restrictions and does not need a node evaluation. `machineOption` forces every node's initial configuration up to the queried path, which costs a few hundred milliseconds per node.
- Selection stays a single-direction relation: nodes are selected for services, never services for nodes. See [D1](#d1-service-level-tags-are-not-supported).
