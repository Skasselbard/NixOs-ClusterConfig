# VM Module — top-level cluster module entry point.
#
# This module registers transformations to:
#      a. Auto-enable microvm.host on machines that host VMs
#      b. Evaluate VM NixOS configs and inject them into host machines

{
  lib,
  clusterlib,
  pkgs,
  flakeInputs,
  ...
}:
let
  # Import the microvm transformation
  microvmTransform = import ./microvm/transformation.nix {
    inherit lib clusterlib flakeInputs pkgs;
  };

in
{
  # ── Extend the cluster type to include a `vms` option ──
  # This adds vms alongside machines in domain.clusters.<name>

  config = {
    extensions = {
      # ── Transformation pipeline ──

      transformations = {
        # Run VM transformations during the cluster transformation stage
        # (before machine NixOS configs are evaluated the first time).

        clusterTransformations = [
          microvmTransform.vmTransformation
        ];

        moduleTransformations = [
          microvmTransform.hostTransformation
        ];
      };
    };
  };
}
