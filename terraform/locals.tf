locals {
  username = "rekyuu"
  main_server_hostname = "koto"
  database_server_hostname = "shoko"
  minecraft_server_hostname = "myoue"

  ssh_agent_identity = file(var.ssh_private_key) == null ? file(var.ssh_public_key) : null
  ssh_client_identity = file(var.ssh_private_key) == null ? file(var.ssh_public_key) : file(var.ssh_private_key)
  ssh_args = "-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o PubkeyAuthentication=yes"
}