terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

provider "proxmox" {
  insecure = true
}