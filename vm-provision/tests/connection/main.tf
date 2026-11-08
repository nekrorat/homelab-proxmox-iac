data "proxmox_virtual_environment_node" "homelab" {
  for_each  = toset(["pve01", "pve02", "pve03"])
  node_name = each.value
}

output "proxmox_nodes" {
  value = sort([
    for node in data.proxmox_virtual_environment_node.homelab :
    node.node_name
  ])
}