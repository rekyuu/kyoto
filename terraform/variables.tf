variable "hcloud_token" {
  sensitive = true
}

// ssh-keygen -t ed25519 -C "your@email.com" -f id_rsa_hetzner
variable "ssh_private_key" {
  default = "~/.ssh/id_rsa_hetzner"
  sensitive = true
}

variable "ssh_public_key" {
  default = "~/.ssh/id_rsa_hetzner.pub"
}

// ssh-keygen -t ed25519 -C "your@email.com" -f id_rsa_hetzner_private
variable "ssh_private_network_private_key" {
  default = "~/.ssh/id_rsa_hetzner_private"
  sensitive = true
}

variable "ssh_private_network_public_key" {
  default = "~/.ssh/id_rsa_hetzner_private.pub"
}

// ssh-keygen -t ed25519 -C "your@email.com" -f id_rsa_hetzner_minecraft
variable "ssh_minecraft_private_key" {
  default = "~/.ssh/id_rsa_hetzner_minecraft"
  sensitive = true
}

variable "ssh_minecraft_public_key" {
  default = "~/.ssh/id_rsa_hetzner_minecraft.pub"
}

variable "zram_size" {
  default = "2G"
}