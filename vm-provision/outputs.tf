output "kubernetes_vms" {
  description = "Kubernetes VM names, IDs, Proxmox hosts, and IP addresses"

  value = {
    for name, vm in var.kubernetes_vms : name => {
      vm_id = vm.vm_id
      node  = vm.node
      ip    = vm.ip
    }
  }
}