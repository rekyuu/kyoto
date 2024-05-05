/*
 * Creates a MicroOS snapshot
 */
packer {
  required_plugins {
    hcloud = {
      version = ">= 1.0.5"
      source  = "github.com/hashicorp/hcloud"
    }
  }
}

variable "hcloud_token" {
  type      = string
  default   = env("HCLOUD_TOKEN")
  sensitive = true
}

# We download the OpenSUSE MicroOS x86 image from an automatically selected mirror.
variable "opensuse_microos_x86_mirror_link" {
  type    = string
  default = "https://download.opensuse.org/tumbleweed/appliances/openSUSE-MicroOS.x86_64-ContainerHost-OpenStack-Cloud.qcow2"
}

locals {
  # Add local variables for inline shell commands
  download_image = "wget --timeout=5 --waitretry=5 --tries=5 --retry-connrefused --inet4-only "

  write_image = <<-EOT
    set -ex
    echo 'MicroOS image loaded, writing to disk... '
    qemu-img convert -p -f qcow2 -O host_device $(ls -a | grep -ie '^opensuse.*microos.*qcow2$') /dev/sda
    echo 'done. Rebooting...'
    sleep 1 && udevadm settle && reboot
  EOT

  // install_packages = <<-EOT
  //   set -ex
  //   echo "First reboot successful, installing k3s..."
  //   curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --cluster-init --write-kubeconfig-mode=644" sh -
  //   sleep 1 && udevadm settle && reboot
  // EOT

  clean_up = <<-EOT
    set -ex
    echo "Second reboot successful, cleaning-up..."
    rm -rf /etc/ssh/ssh_host_*
    echo "Make sure to use NetworkManager"
    touch /etc/NetworkManager/NetworkManager.conf
    sleep 1 && udevadm settle
  EOT
}

# Source for the MicroOS x86 snapshot
source "hcloud" "microos-x86-snapshot" {
  image = "ubuntu-22.04"
  rescue = "linux64"
  location = "fsn1"
  server_type = "cpx11" # disk size of >= 40GiB is needed to install the MicroOS image
  snapshot_labels = {
    os = "opensuse",
    arch = "x86_64"
  }
  snapshot_name = "openSUSE MicroOS x86_64"
  ssh_username = "root"
  token = var.hcloud_token
}

# Build the MicroOS x86 snapshot
build {
  sources = ["source.hcloud.microos-x86-snapshot"]

  # Download the MicroOS x86 image
  provisioner "shell" {
    inline = ["${local.download_image}${var.opensuse_microos_x86_mirror_link}"]
  }

  # Write the MicroOS x86 image to disk
  provisioner "shell" {
    inline = [local.write_image]
    expect_disconnect = true
  }

  # Ensure connection to MicroOS x86 and do house-keeping
  // provisioner "shell" {
  //   pause_before      = "5s"
  //   inline            = [local.install_packages]
  //   expect_disconnect = true
  // }

  # Ensure connection to MicroOS x86 and do house-keeping
  provisioner "shell" {
    pause_before = "5s"
    inline = [local.clean_up]
  }
}