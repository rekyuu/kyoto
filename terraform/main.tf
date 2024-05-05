// Create the SSH keys
resource "hcloud_ssh_key" "default" {
  name = "Default"
  public_key = file(var.ssh_public_key)
}

resource "hcloud_ssh_key" "private" {
  name = "Private"
  public_key = file(var.ssh_private_network_public_key)
}

// Create the internal network
resource "hcloud_network" "network" {
  name = "network"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "network_subnet" {
  type = "cloud"
  network_id = hcloud_network.network.id
  network_zone = "us-east"
  ip_range = "10.0.1.0/24"
}

resource "hcloud_primary_ip" "main_ipv4" {
  name = "${local.main_server_hostname}-ipv4"
  type = "ipv4"
  datacenter = "ash-dc1"
  assignee_type = "server"
  auto_delete = false
}

resource "hcloud_primary_ip" "main_ipv6" {
  name = "${local.main_server_hostname}-ipv6"
  type = "ipv6"
  datacenter = "ash-dc1"
  assignee_type = "server"
  auto_delete = false
}

resource "hcloud_primary_ip" "database_ipv4" {
  name = "${local.database_server_hostname}-ipv4"
  type = "ipv4"
  datacenter = "ash-dc1"
  assignee_type = "server"
  auto_delete = false
}

resource "hcloud_primary_ip" "database_ipv6" {
  name = "${local.database_server_hostname}-ipv6"
  type = "ipv6"
  datacenter = "ash-dc1"
  assignee_type = "server"
  auto_delete = false
}

// Create the firewall
resource "hcloud_firewall" "public_firewall" {
  name = "public-firewall"
  
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
    description = "Kubernetes API"
    direction = "in"
    protocol  = "tcp"
    port = "6443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}

resource "hcloud_firewall" "private_firewall" {
  name = "private-firewall"
  
  rule {
    description = "Ping"
    direction = "in"
    protocol = "icmp"
    source_ips = [
      "10.0.0.0/16"
    ]
  }

  rule {
    description = "Any TCP" 
    direction = "in"
    protocol  = "tcp"
    port = "any"
    source_ips = [
      "10.0.0.0/16"
    ]
  }
}

// Create random string for temp ssh identity file
resource "random_string" "identity_file" {
  length  = 20
  lower   = true
  special = false
  numeric = true
  upper   = false
}

// Create the main server
resource "hcloud_server" "main_server" {
  depends_on = [ hcloud_network_subnet.network_subnet ]

  lifecycle {
    ignore_changes = [
      location,
      ssh_keys,
      user_data,
      image,
    ]
  }

  name = local.main_server_hostname
  image = data.hcloud_image.opensuse_snapshot.id // Created by opensuse-snapshot.pkr.hcl
  server_type = "cpx41" // Shared, 8 AMD VCPU, 16G RAM, 240GB SSD
  location = "ash"
  firewall_ids = [ hcloud_firewall.public_firewall.id ]
  user_data = data.cloudinit_config.koto_config.rendered
  ssh_keys = [ hcloud_ssh_key.default.id ]

  public_net {
    ipv4 = hcloud_primary_ip.main_ipv4.id
    ipv6 = hcloud_primary_ip.main_ipv6.id
  }

  network {
    network_id = hcloud_network.network.id
    ip = "10.0.1.2"
    alias_ips = []
  }

  connection {
    user = "root"
    private_key = file(var.ssh_private_key)
    agent_identity = local.ssh_agent_identity
    host = self.ipv4_address
  }

  // Prepare ssh identity file
  provisioner "local-exec" {
    command = <<-EOT
      install -b -m 600 /dev/null /tmp/${random_string.identity_file.id}
      echo "${local.ssh_client_identity}" | sed 's/\r$//' > /tmp/${random_string.identity_file.id}
    EOT
  }

  // Wait for the server to come online
  provisioner "local-exec" {
    command = <<-EOT
      until ssh ${local.ssh_args} -i /tmp/${random_string.identity_file.id} -o ConnectTimeout=2 root@${self.ipv4_address} true 2> /dev/null
      do
        echo "Waiting for MicroOS to become available..."
        sleep 3
      done
    EOT
  }

  // Cleanup ssh identity file
  provisioner "local-exec" {
    command = <<-EOT
      rm /tmp/${random_string.identity_file.id}
    EOT
  }

  // Install k3s
  provisioner "remote-exec" {
    inline = ["curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --cluster-init --write-kubeconfig-mode=644' sh -"]
  }

  // Create the private network ssh key
  provisioner "file" {
    content = file(var.ssh_private_network_private_key)
    destination = "/home/${local.username}/.ssh/id_rsa"
  }

  // Create k3s-swapoff script
  provisioner "file" {
    content = <<-EOT
#!/bin/bash

# Switching off swap
swapoff /dev/zram0

rmmod zram
    EOT
    destination = "/usr/local/bin/k3s-swapoff"
  }

  // Create k3s-swapon script
  provisioner "file" {
    content = <<-EOT
#!/bin/bash

# get the amount of memory in the machine
# load the dependency module
modprobe zram

# initialize the device with zstd compression algorithm
echo zstd > /sys/block/zram0/comp_algorithm;
echo ${var.zram_size} > /sys/block/zram0/disksize

# Creating the swap filesystem
mkswap /dev/zram0

# Switch the swaps on
swapon -p 100 /dev/zram0
    EOT
    destination = "/usr/local/bin/k3s-swapon"
  }

  // Create zram systemd unit
  provisioner "file" {
    content = <<-EOT
[Unit]
Description=Swap with zram
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/usr/local/bin/k3s-swapon
ExecStop=/usr/local/bin/k3s-swapoff

[Install]
WantedBy=multi-user.target
    EOT
    destination = "/etc/systemd/system/zram.service"
  }

  // Enable zram
  provisioner "remote-exec" {
    inline = [
      "chmod +x /usr/local/bin/k3s-swapon",
      "chmod +x /usr/local/bin/k3s-swapoff",
      "systemctl disable --now zram.service",
      "systemctl enable --now zram.service"
    ]
  }

  // Update Traefik config
  provisioner "remote-exec" {
    inline = ["mkdir -p /var/lib/rancher/k3s/server/manifests"]
  }

  provisioner "file" {
    content = <<-EOT
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    globalArguments: []
    ports:
      web:
        redirectTo:
          port: websecure
        proxyProtocol:
          trustedIPs:
            - 127.0.0.1/32
            - 10.0.0.0/8        
        forwardedHeaders:
          trustedIPs:
            - 127.0.0.1/32
            - 10.0.0.0/8
      websecure:
        proxyProtocol:
          trustedIPs:
            - 127.0.0.1/32
            - 10.0.0.0/8        
        forwardedHeaders:
          trustedIPs:
            - 127.0.0.1/32
            - 10.0.0.0/8
    EOT
    destination = "/var/lib/rancher/k3s/server/manifests/traefik-config.yaml"
  }

  // Lock down SSH
  provisioner "remote-exec" {
    inline = [
      "touch /etc/ssh/sshd_config.d/auth.conf",
      "echo 'PermitRootLogin no' >> /etc/ssh/sshd_config.d/auth.conf",
      "echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config.d/auth.conf",
      "echo 'KbdInteractiveAuthentication no' >> /etc/ssh/sshd_config.d/auth.conf",
      "echo 'ChallengeResponseAuthentication no' >> /etc/ssh/sshd_config.d/auth.conf",
      "echo 'MaxAuthTries 2' >> /etc/ssh/sshd_config.d/auth.conf",
      "echo 'AllowTcpForwarding no' >> /etc/ssh/sshd_config.d/auth.conf",
      "echo 'X11Forwarding no' >> /etc/ssh/sshd_config.d/auth.conf",
      "echo 'AllowAgentForwarding no' >> /etc/ssh/sshd_config.d/auth.conf",
      "echo 'AuthorizedKeysFile .ssh/authorized_keys' >> /etc/ssh/sshd_config.d/auth.conf",
    ]
  }

  // Reboot
  provisioner "remote-exec" {
    inline = ["udevadm settle && reboot"]
  }
}

// Create the database server
resource "hcloud_server" "database_server" {
  depends_on = [ hcloud_network_subnet.network_subnet ]

  lifecycle {
    ignore_changes = [
      location,
      ssh_keys,
      user_data,
      image,
    ]
  }

  name = local.database_server_hostname
  image = "rocky-9"
  server_type = "cpx11" // Shared, 2 AMD VCPU, 2G RAM, 40GB SSD
  location = "ash"
  firewall_ids = [ hcloud_firewall.private_firewall.id ]
  user_data = data.cloudinit_config.shoko_config.rendered
  ssh_keys = [ hcloud_ssh_key.private.id ]

  public_net {
    ipv4 = hcloud_primary_ip.database_ipv4.id
    ipv6 = hcloud_primary_ip.database_ipv6.id
  }

  network {
    network_id = hcloud_network.network.id
    ip = "10.0.1.3"
    alias_ips = []
  }
}