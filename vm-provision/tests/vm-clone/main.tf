resource "proxmox_virtual_environment_vm" "ubuntu_test" {
  name      = "ubuntu-test"
  node_name = "pve01"
  vm_id     = 100

  started         = true
  stop_on_destroy = true

  clone {
    vm_id = 9000
    full  = true
  }

  agent {
    enabled = false
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "192.168.8.37/24"
        gateway = "192.168.8.1"
      }
    }

    user_account {
      username = "ubuntu"
      keys = [
        trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))
      ]
    }
  }
}