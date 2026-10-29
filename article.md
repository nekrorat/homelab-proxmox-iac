# Kubernetes Homelab Part 3: Automating Proxmox and Provisioning Ubuntu VMs

In [Part 1: Physical Network](https://www.linkedin.com/pulse/kubernetes-homelab-part-1-physical-network-rasul-abdulmagomedov-vafwe/), we connected the physical hardware and created a dedicated network for our Kubernetes homelab.

In [Part 2: Automating Proxmox Installation with PXE/iPXE](https://www.linkedin.com/pulse/kubernetes-homelab-part-2-automating-proxmox-pxe-abdulmagomedov-fieqe/), we automated the installation of Proxmox VE on three physical machines.

At this point, we have three Proxmox servers running, but we still don't have a Kubernetes cluster.

The next challenge is to configure those servers and create the virtual machines that will eventually run Kubernetes.

We could do much of this manually through the Proxmox web interface and SSH. However, my goal for this homelab is to learn how to manage infrastructure through code, rather than repeat the same installation steps every time.

For this part, we will use **Ansible** to configure Proxmox and **Terraform** to provision our Ubuntu virtual machines. In Part 4, we'll configure Ubuntu and install Kubernetes.

All configuration files are available in the [Homelab Proxmox IaC repository](https://github.com/nekrorat/homelab-proxmox-iac).

The repository also contains [tests.md](https://github.com/nekrorat/homelab-proxmox-iac/blob/main/tests.md), with verification commands organized by the same step numbers used in this article. Use it whenever you want to check a specific stage or troubleshoot an installation.

## What Are We Building?

Our physical setup has not changed since Part 2. We still have three HP EliteDesk mini PCs running Proxmox VE on the dedicated homelab network.

![[k8-network.png]]

This time, we will create six Ubuntu virtual machines across those three physical servers.

|Proxmox host|Virtual machine|IP address|
|---|---|---|
|pve01|control-plane-01|192.168.8.31|
|pve01|worker-01|192.168.8.32|
|pve02|worker-02|192.168.8.33|
|pve02|worker-03|192.168.8.34|
|pve03|worker-04|192.168.8.35|
|pve03|worker-05|192.168.8.36|

Every VM will have:

- Ubuntu Server 24.04

- 2 CPU cores

- 4 GB RAM

- 25 GB disk


One VM will act as the **Kubernetes control plane**, and the remaining five will become **worker nodes**.

The control plane manages the cluster. Worker nodes are where our application workloads will run.

In this article, we will complete the first two stages:

1. **Ansible:** Configure Proxmox hosts, create a Proxmox cluster, and prepare an Ubuntu VM template.
2. **Terraform:** Provision six Ubuntu virtual machines.

**Part 4** will cover the remaining two stages: configuring Ubuntu and installing Kubernetes with Ansible.


### Why Use Both Ansible and Terraform?

Ansible and Terraform solve different problems.

**Ansible** is a configuration automation tool. We can use it to install software, configure operating systems, change settings, and run tasks on remote machines over SSH.

**Terraform** is an Infrastructure as Code tool. In this project, we use it to describe the virtual machines we want Proxmox to create.

For example, Terraform creates a VM with 4 GB RAM and a specific IP address. Ansible then connects to that VM and installs the software needed to make it a Kubernetes node.

Using them together allows us to automate both infrastructure provisioning and operating system configuration.

Let's get started.

---

## Step 1: Configure Proxmox with Ansible

In [Part 2](https://www.linkedin.com/pulse/kubernetes-homelab-part-2-automating-proxmox-pxe-abdulmagomedov-fieqe/) we successfully installed Proxmox VE on all three physical machines.

Now we need to prepare those machines for hosting our Kubernetes virtual machines.

Our Proxmox configuration will handle several tasks:

- Configure the Proxmox package repositories and install updates.

- Configure hostnames and local host resolution.

- Create a Proxmox cluster named `homelab`.

- Create an API token that Terraform can use.

- Prepare an Ubuntu Cloud-Init template for provisioning virtual machines.


Instead of connecting to each physical server and repeating these steps manually, we will use an Ansible playbook.

### Step 1.1: Prepare the Repository

On the Management PC, clone the repository:

```
git clone https://github.com/nekrorat/homelab-proxmox-iac.git

cd homelab-proxmox-iac
```

Make sure Ansible, Terraform, Git, SSH, and OpenSSL are installed. The repository's README contains the prerequisites and environment-specific settings to review before proceeding.

Our repository separates the automation into four directories:

```
homelab-proxmox-iac/
├── proxmox-config/          # Step 1
├── vm-provision/            # Step 2
├── ubuntu-config/           # Step 3
└── kubernetes-config/       # Step 4
```

We will work through them in this order.

### Step 1.2: Configure the Ansible Inventory

The first file we need is:

```
proxmox-config/inventory/hosts.ini
```

It contains the Proxmox servers that Ansible will manage:

```
[proxmox]
pve01 ansible_host=192.168.8.21
pve02 ansible_host=192.168.8.22
pve03 ansible_host=192.168.8.23

[proxmox:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3.13
```

An **inventory** is simply a list of machines that Ansible can connect to.

The `[proxmox]` group allows us to target all three physical servers together, while `ansible_user=root` tells Ansible which account to use for SSH.

Before proceeding, make sure you can connect to those servers using SSH.

You can also test Ansible connectivity:

```
ansible proxmox \
  -i proxmox-config/inventory/hosts.ini \
  -m ansible.builtin.ping
```

If each host responds with `pong`, Ansible can communicate with the servers.

### Step 1.3: Review the Proxmox Playbook

Our main playbook is:

```
proxmox-config/configure-proxmox.yaml
```

Before running the playbook, let's look at the tasks it performs on the three hosts.

### Step 1.4: Configure Proxmox Package Repositories

The first tasks disable the enterprise package repositories and configure the Proxmox no-subscription repository.

This lets our homelab receive Proxmox package updates without an enterprise subscription.

### Step 1.5: Remove the Subscription Reminder (Optional)

The playbook also includes a cosmetic customization for removing the Proxmox subscription reminder.

This is specific to my homelab and is not required for Kubernetes or Proxmox clustering.

### Step 1.6: Upgrade Proxmox Packages

Ansible updates the package lists, upgrades installed packages, and reboots a host if the operating system indicates a reboot is required.

### Step 1.7: Configure Hostnames and Name Resolution

Each Proxmox host is assigned its hostname and receives entries for the other Proxmox nodes in `/etc/hosts`.

This makes it possible for the hosts to resolve names such as `pve01` and `pve02` to their network addresses.

### Step 1.8: Verify Proxmox Host Connectivity

Before clustering the servers, the playbook checks that the Proxmox hosts can reach each other.

If name resolution or connectivity fails, we should fix that before attempting to join the cluster.

### Step 1.9: Create the Proxmox Cluster

Now we create a **Proxmox cluster**.

A Proxmox cluster allows multiple physical virtualization hosts to be managed together. Instead of managing each server through a completely separate interface, we can see and manage all three through one Proxmox Datacenter view.

Ansible initializes the cluster on `pve01` and joins `pve02` and `pve03`.

The underlying Proxmox commands are:

```
pvecm create homelab --link0 192.168.8.21
```

On the additional nodes:

```
pvecm add 192.168.8.21 --use_ssh
```

Our playbook automates these operations, including the SSH configuration needed between the hosts.

It also checks whether the cluster configuration already exists so it doesn't recreate the cluster during a normal rerun.

One important distinction: **the Proxmox cluster and Kubernetes cluster are not the same thing**.

The Proxmox cluster manages our physical virtualization infrastructure. Later, the Kubernetes cluster will manage applications running inside the Ubuntu VMs.

### Step 1.10: Create Terraform API Access

Terraform needs a way to communicate with Proxmox.

Instead of using SSH to create each virtual machine, Terraform interacts with the Proxmox API.

Our Ansible playbook creates a Terraform API token and saves the required connection settings locally:

```
proxmox-config/terraform-api-token.env
```

This file contains the Proxmox API endpoint and token.

We can load it into our Management PC terminal using:

```
source proxmox-config/terraform-api-token.env
```

The file is excluded from Git because the token is sensitive.

The example uses a powerful API token for this isolated homelab. In a shared or production environment, permissions should be more restrictive.

### Step 1.11: Prepare the Ubuntu Cloud-Init Template

Next, we need a reusable Ubuntu image.

Creating six virtual machines by manually installing Ubuntu six times would work, but it would defeat much of the purpose of this automation.

Instead, we use an **Ubuntu Cloud-Init image**.

Cloud-Init is a tool that allows a virtual machine to receive its initial configuration automatically during first boot. This can include its hostname, network configuration, SSH keys, and user account.

Our Ansible playbook downloads the Ubuntu 24.04 cloud image and creates a Proxmox VM template with ID `9000` on `pve01`.

Think of this template as the starting point for every Kubernetes virtual machine we will create.

We prepare it once and clone it whenever we need another VM.

### Step 1.12: Run the Proxmox Playbook

From the repository root:

```
ansible-playbook \
  -i proxmox-config/inventory/hosts.ini \
  proxmox-config/configure-proxmox.yaml
```

Ansible will work through the Proxmox configuration, cluster creation, API access, and Ubuntu template preparation.

**Verify Step 1**

After the playbook completes, connect to a Proxmox host and run:

```
pvecm status
pvecm nodes
```

We should see all three Proxmox hosts participating in the `homelab` cluster.

On `pve01`, we can also check our Ubuntu template:

```
qm config 9000
```


At this point, we have a configured Proxmox cluster and a reusable Ubuntu template.

---

## Step 2: Provision Ubuntu VMs with Terraform

Now comes one of my favorite parts of this project.

Instead of opening the Proxmox web interface and clicking through the virtual machine creation wizard six times, we will define all six machines in Terraform.

The Terraform configuration lives in:

```
vm-provision/
├── main.tf
├── variables.tf
├── providers.tf
└── outputs.tf
```

Each file has a purpose:

- `providers.tf` configures the Proxmox Terraform provider.

- `variables.tf` contains VM names, IP addresses, VM IDs, and other settings.

- `main.tf` defines how to create the virtual machines.

- `outputs.tf` displays useful information after provisioning.


### Step 2.1: Define the Virtual Machines

In `variables.tf`, we describe the Kubernetes VMs using a Terraform map.

For example, the configuration includes entries like these:

```
control-plane-01 = {
  vm_id = 101
  node  = "pve01"
  ip    = "192.168.8.31"
}

worker-01 = {
  vm_id = 102
  node  = "pve01"
  ip    = "192.168.8.32"
}
```

These are excerpts from the VM map. The repository contains all six definitions.

Each entry tells Terraform which VM to create, where to place it, and which IP address it should use.

Inside `main.tf`, we use:

```
resource "proxmox_virtual_environment_vm" "kubernetes" {
  for_each = var.kubernetes_vms

  name      = each.key
  node_name = each.value.node
  vm_id     = each.value.vm_id

  # Additional VM settings
}
```

The important part is `for_each`.

Instead of writing six nearly identical Terraform resources, we define one resource that Terraform repeats for every VM in our map.

The full configuration also defines the CPU, RAM, disk, network bridge, SSH public key, and Cloud-Init settings.

Every VM is cloned from the Ubuntu template we created in Step 1.

### Step 2.2: Test Terraform's Proxmox Connection (Optional)

Before creating our six VMs, the repository provides a small Terraform test that queries the Proxmox API for the available node names.

It is useful for verifying the API endpoint and token without provisioning a VM.

### Step 2.3: Test the Ubuntu Template Clone (Optional)

Another small Terraform test can create a temporary Ubuntu VM from our template.

This confirms the template is usable before we attempt to provision all six Kubernetes VMs. The test uses VM ID `100` and IP `192.168.8.37`, so make sure those values are available first.

After testing, remove the temporary VM using the test directory's own Terraform state, not the state that manages our Kubernetes nodes.

### Step 2.4: Initialize and Deploy


First, load the Proxmox API credentials if you haven't already:

```
source proxmox-config/terraform-api-token.env
```

Initialize Terraform:

```
terraform -chdir=vm-provision init
```

This downloads and prepares the provider needed to communicate with Proxmox.

Next, preview the infrastructure changes:

```
terraform -chdir=vm-provision plan
```

Terraform compares the configuration against its recorded state and shows what it intends to create, modify, or remove.

For a fresh environment, we should expect six virtual machines to be created.

Once the plan looks correct, apply it:

```
terraform -chdir=vm-provision apply
```

Terraform connects to Proxmox through the API and begins cloning the Ubuntu template.

After provisioning finishes, all six VMs should appear across our three Proxmox hosts.

### Step 2.5: Verify the Virtual Machines

Terraform can show us the deployed VM information:

```
terraform -chdir=vm-provision output kubernetes_vms
```

We can also test SSH access:

```
ssh ubuntu@192.168.8.31
```

If we can log in to the control-plane VM, our Cloud-Init configuration and SSH key setup are working for that machine.


**An important lesson about Terraform:** It maintains a state file that records the resources it manages. That state should be protected and backed up.

Also, don't use `terraform destroy` in the main VM directory unless you intentionally want to remove the Kubernetes virtual machines.

With our six virtual machines running, the infrastructure provisioning phase is complete. In Part 4, we'll prepare Ubuntu and install Kubernetes.

---

## Wrap-Up

We started with three physical servers running Proxmox VE. Using Ansible, we configured the hosts, created the `homelab` Proxmox cluster, set up Terraform API access, and prepared a reusable Ubuntu 24.04 Cloud-Init template.

Then we used Terraform to clone that template into six virtual machines across the three physical servers. We defined the VM names, network addresses, CPU, memory, and storage in code instead of repeating the same steps through the Proxmox web interface.

**We now have the infrastructure for our Kubernetes cluster, but Kubernetes is not installed yet.**

In **[Part 4: Configuring Ubuntu and Installing Kubernetes with Ansible](article-part-4.md)**, we will prepare the six Ubuntu VMs, install the Kubernetes components, join the workers, configure Cilium networking, and run a smoke test.

The complete infrastructure code and the step-by-step test commands remain together in the [Homelab Proxmox IaC repository](https://github.com/nekrorat/homelab-proxmox-iac).

#Proxmox #Terraform #Ansible #Homelab #DevOps #InfrastructureAsCode
