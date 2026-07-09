{
  # FIXME: This is a workaround to disable Home Manager's manpage generation, which fails in this VM setup since 26.05. It should be removed once the build succeedes again.
  home-manager.sharedModules = [
    { manual.manpages.enable = false; }
  ];
}
