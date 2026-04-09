# Example secrets used across all examples.
#
# WARNING: These are PUBLIC example credentials!
# In a real project, never commit plaintext passwords or private keys to version control.
# Use a secrets manager or encrypted files instead.
{
  # Hashed passwords generated with `mkpasswd -m sha-512 <password>`
  # To generate your own: nix-shell -p mkpasswd --run 'mkpasswd -m sha-512'

  # password = 'root'
  pswdHash.root = "$6$gV1emEujFxua0zY1$4gq.RTxDX8EY30vIL1PSk4Qa9xJVxbP5.Dz87t0yElZRyFGaDyN8SF35lMofZ7OTGuKRGxyUSEBpYY/2BKQvj/";

  # password = 'admin'
  pswdHash.admin = "$6$60vBYZVRuV8HwUQI$K8nOgQgVQcNnlku3MBGMoAMU4o5heXCg2CPaX3/4InSJCTeJgqU3bPEF2.hibMY0tOx8dHNGE61lqEe.Rchxa/";

  # SSH key pair for remote access.
  # The private key is added to the SSH agent on the build machine.
  # The public key is deployed to the target machines via openssh.authorizedKeys.
  ssh.privateKey = builtins.readFile ./sshKey;
  ssh.publicKey = builtins.readFile ./sshKey.pub;
}
