{
  # result of ``mkpasswd -m sha-512 root``
  pswdHash.root =
    "$6$gV1emEujFxua0zY1$4gq.RTxDX8EY30vIL1PSk4Qa9xJVxbP5.Dz87t0yElZRyFGaDyN8SF35lMofZ7OTGuKRGxyUSEBpYY/2BKQvj/";
  ssh.privateKey = builtins.readFile ./sshKey;
  ssh.publicKey = builtins.readFile ./sshKey.pub;
}
