# Default Home Manager module.
#
# This is the minimum required Home Manager configuration.
# When ANY cluster user has homeManagerModules, ALL users must include
# a module that sets `home.stateVersion`. This module does exactly that.
#
# The `_class = "homeManager"` attribute marks this as a Home Manager module
# (as opposed to a NixOS module). This is required by Home Manager.
{
  _class = "homeManager";

  # Must match or be older than your NixOS system.stateVersion.
  home.stateVersion = "24.05";

  # Disable Home Manager's self-management — NixOS handles activation.
  programs.home-manager.enable = false;

}
