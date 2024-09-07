{
  _class = "homeManager";

  home.stateVersion = "24.05";

  # Manage HomeManager with NixOs and not by itself
  programs.home-manager.enable = false;

}
