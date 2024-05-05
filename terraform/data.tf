data "hcloud_image" "opensuse_snapshot" {
  with_selector = "os=opensuse,arch=x86_64"
  most_recent = true
}

data "cloudinit_config" "koto_config" {
  gzip = true
  base64_encode = true

  part {
    filename = "init.cfg"
    content_type = "text/cloud-config"
    content = <<-EOT
    #cloud-config

    debug: True

    users:
      - name: ${local.username}
        groups: users
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        ssh_authorized_keys:
          - ${file(var.ssh_public_key)}

    # Resize /var, not /, as that's the last partition in MicroOS image.
    growpart:
      devices: ["/var"]

    # Make sure the hostname is set correctly
    hostname: ${local.main_server_hostname}
    preserve_hostname: true

    runcmd:
      # ensure that /var uses full available disk size, thanks to btrfs this is easy
      - [btrfs, 'filesystem', 'resize', 'max', '/var']
      # Bounds the amount of logs that can survive on the system
      - [sed, '-i', 's/#SystemMaxUse=/SystemMaxUse=3G/g', /etc/systemd/journald.conf]
      - [sed, '-i', 's/#MaxRetentionSec=/MaxRetentionSec=1week/g', /etc/systemd/journald.conf]
      # Disable transactional updates
      - systemctl disable transactional-update.timer
      # Reboot
      - udevadm settle && reboot
    EOT
  }
}

data "cloudinit_config" "shoko_config" {
  gzip = true
  base64_encode = true

  part {
    filename = "init.cfg"
    content_type = "text/cloud-config"
    content = <<-EOT
    #cloud-config

    debug: True

    users:
      - name: ${local.username}
        groups: users docker
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        ssh_authorized_keys:
          - ${file(var.ssh_private_network_public_key)}

    # Make sure the hostname is set correctly
    hostname: ${local.database_server_hostname}
    preserve_hostname: true

    runcmd:
      # Install and enable docker
      - dnf check-update
      - dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      - dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin vim postgres sssd
      - systemctl enable docker
      # Bounds the amount of logs that can survive on the system
      - [sed, '-i', 's/#SystemMaxUse=/SystemMaxUse=3G/g', /etc/systemd/journald.conf]
      - [sed, '-i', 's/#MaxRetentionSec=/MaxRetentionSec=1week/g', /etc/systemd/journald.conf]
      # Lock down SSH
      - sed -i -e '/^\(#\|\)PermitRootLogin/s/^.*$/PermitRootLogin no/' /etc/ssh/sshd_config
      - sed -i -e '/^\(#\|\)PasswordAuthentication/s/^.*$/PasswordAuthentication no/' /etc/ssh/sshd_config
      - sed -i -e '/^\(#\|\)KbdInteractiveAuthentication/s/^.*$/KbdInteractiveAuthentication no/' /etc/ssh/sshd_config
      - sed -i -e '/^\(#\|\)ChallengeResponseAuthentication/s/^.*$/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
      - sed -i -e '/^\(#\|\)MaxAuthTries/s/^.*$/MaxAuthTries 2/' /etc/ssh/sshd_config
      - sed -i -e '/^\(#\|\)AllowTcpForwarding/s/^.*$/AllowTcpForwarding no/' /etc/ssh/sshd_config
      - sed -i -e '/^\(#\|\)X11Forwarding/s/^.*$/X11Forwarding no/' /etc/ssh/sshd_config
      - sed -i -e '/^\(#\|\)AllowAgentForwarding/s/^.*$/AllowAgentForwarding no/' /etc/ssh/sshd_config
      - sed -i -e '/^\(#\|\)AuthorizedKeysFile/s/^.*$/AuthorizedKeysFile .ssh\/authorized_keys/' /etc/ssh/sshd_config
      # Reboot
      - udevadm settle && reboot
    EOT
  }
}