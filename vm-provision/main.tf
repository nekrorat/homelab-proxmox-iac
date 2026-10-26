resource "proxmox_virtual_environment_vm" "kubernetes" {
  for_each = var.kubernetes_vms

  name      = each.key
  node_name = each.value.node
  vm_id     = each.value.vm_id

  started         = true
  stop_on_destroy = true

  clone {
    vm_id        = var.template_vm_id
    node_name    = var.template_node
    datastore_id = var.datastore
    full         = true
  }

  cpu {
    cores = var.vm_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.vm_memory
  }

  disk {
    datastore_id = var.datastore
    interface    = "scsi0"
    size         = var.vm_disk_size
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  agent {
    enabled = false
  }

  vga {
    type = "std"
  }

  initialization {
    datastore_id = var.datastore

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.gateway
      }
    }

    user_account {
      username = "ubuntu"
      keys = [
        trimspace(file(pathexpand(var.ssh_public_key_path)))
      ]
    }
  }
}