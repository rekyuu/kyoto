// Create the SSH keys
resource "hcloud_ssh_key" "minecraft" {
  name = "Minecraft"
  public_key = file(var.ssh_minecraft_public_key)
}

// Create the internal network
resource "hcloud_primary_ip" "minecraft_ipv4" {
  name = "${local.minecraft_server_hostname}-ipv4"
  type = "ipv4"
  datacenter = "ash-dc1"
  assignee_type = "server"
  auto_delete = false
  delete_protection = true
}

resource "hcloud_primary_ip" "minecraft_ipv6" {
  name = "${local.minecraft_server_hostname}-ipv6"
  type = "ipv6"
  datacenter = "ash-dc1"
  assignee_type = "server"
  auto_delete = false
  delete_protection = true
}

resource "hcloud_network" "minecraft_network" {
  name = "minecraft-network"
  ip_range = "10.1.0.0/16"
  delete_protection = true
}

resource "hcloud_network_subnet" "minecraft_network_subnet" {
  type = "cloud"
  network_id = hcloud_network.minecraft_network.id
  network_zone = "us-east"
  ip_range = "10.1.1.0/24"
}

// Create the firewall
resource "hcloud_firewall" "minecraft_firewall" {
  name = "minecraft-firewall"
  
  rule {
    description = "Ping"
    direction = "in"
    protocol = "icmp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    description = "HTTP"
    direction = "in"
    protocol  = "tcp"
    port = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    description = "HTTPS"
    direction = "in"
    protocol  = "tcp"
    port = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    description = "SSH"
    direction = "in"
    protocol  = "tcp"
    port = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    description = "Minecraft"
    direction = "in"
    protocol  = "tcp"
    port = "25565"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    description = "Minecraft"
    direction = "in"
    protocol  = "udp"
    port = "25565"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}

// Create the Minecraft server
resource "hcloud_server" "minecraft_server" {
  depends_on = [ hcloud_network_subnet.minecraft_network_subnet ]
  delete_protection = true
  rebuild_protection = true

  lifecycle {
    ignore_changes = [
      location,
      ssh_keys,
      user_data,
      image,
    ]
  }

  name = local.minecraft_server_hostname
  image = "rocky-9"
  server_type = "ccx23" // Dedicated, 4 AMD VCPU, 16GB RAM, 160GB SSD
  location = "ash"
  firewall_ids = [ hcloud_firewall.minecraft_firewall.id ]
  user_data = data.cloudinit_config.myoue_config.rendered
  ssh_keys = [ hcloud_ssh_key.minecraft.id ]

  public_net {
    ipv4 = hcloud_primary_ip.minecraft_ipv4.id
    ipv6 = hcloud_primary_ip.minecraft_ipv6.id
  }

  network {
    network_id = hcloud_network.minecraft_network.id
    ip = "10.1.1.2"
    alias_ips = []
  }
}