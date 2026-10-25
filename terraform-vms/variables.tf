variable "kubernetes_vms" {
  description = "Kubernetes VM names, IDs, Proxmox nodes, and static IPs"

  type = map(object({
    vm_id = number
    node  = string
    ip    = string
  }))

  default = {
    control-plane-01 = { vm_id = 101, node = "pve01", ip = "192.168.8.31" }
    worker-01        = { vm_id = 102, node = "pve01", ip = "192.168.8.32" }
    worker-02        = { vm_id = 103, node = "pve02", ip = "192.168.8.33" }
    worker-03        = { vm_id = 104, node = "pve02", ip = "192.168.8.34" }
    worker-04        = { vm_id = 105, node = "pve03", ip = "192.168.8.35" }
    worker-05        = { vm_id = 106, node = "pve03", ip = "192.168.8.36" }
  }
}

variable "template_vm_id"      { type = number, default = 9000 }
variable "template_node"       { type = string, default = "pve01" }
variable "datastore"           { type = string, default = "local-lvm" }
variable "network_bridge"      { type = string, default = "vmbr0" }
variable "gateway"             { type = string, default = "192.168.8.1" }
variable "ssh_public_key_path" { type = string, default = "~/.ssh/id_ed25519.pub" }
variable "vm_cores"            { type = number, default = 2 }
variable "vm_memory"           { type = number, default = 4096 }
variable "vm_disk_size"        { type = number, default = 25 }