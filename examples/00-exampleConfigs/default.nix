{
  secrets = import ./secrets;
  machines = { vm = import ./machines/vm.nix; };
}
