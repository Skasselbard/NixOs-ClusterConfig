{
  # result of ``mkpasswd -m sha-512 root``
  pswdHash.root =
    "$6$gV1emEujFxua0zY1$4gq.RTxDX8EY30vIL1PSk4Qa9xJVxbP5.Dz87t0yElZRyFGaDyN8SF35lMofZ7OTGuKRGxyUSEBpYY/2BKQvj/";
  # ``mkpasswd -m sha-512 admin``
  pswdHash.admin =
    "$6$60vBYZVRuV8HwUQI$K8nOgQgVQcNnlku3MBGMoAMU4o5heXCg2CPaX3/4InSJCTeJgqU3bPEF2.hibMY0tOx8dHNGE61lqEe.Rchxa/";
  ssh.privateKey = builtins.readFile ./sshKey;
  ssh.publicKey = builtins.readFile ./sshKey.pub;
}
