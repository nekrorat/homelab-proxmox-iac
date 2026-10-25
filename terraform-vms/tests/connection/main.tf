data "proxmox_virtual_environment_nodes" "homelab" {}

output "proxmox_nodes" {
  value = data.proxmox_virtual_environment_nodes.homelab.names
}