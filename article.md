13 Disable Subscribption Warning
20 (1400) Update proxmox pakages

![[Pasted image 20261017235440.png]]

1.4 Configure Proxmox

How to Disable the Proxmox Enterprise Repository and Enable the No-Subscription Repository
https://syncbricks.com/how-to-disable-the-proxmox-enterprise-repository-and-enable-the-no-subscription-repository/

Proxmox VE No-Subscription Repository
https://pve.proxmox.com/wiki/Package_Repositories

Remove subscription warning
https://syncbricks.com/how-to-disable-the-proxmox-subscription-nag-warning/


ansible-playbook \                            
-i proxmox-ansible-config/inventory/hosts.ini \
proxmox-ansible-config/configure-proxmox.yaml

How to Use Ansible to Set Up a Kubernetes Cluster from Scratch
https://oneuptime.com/blog/post/2026-02-21-how-to-use-ansible-to-set-up-a-kubernetes-cluster-from-scratch/view


---

In [Part 1: Physical Network](https://www.linkedin.com/pulse/kubernetes-homelab-part-1-physical-network-rasul-abdulmagomedov-vafwe/), we connected the physical hardware and created a dedicated network for our Kubernetes homelab.

In [Part 2: Automating Proxmox Installation with PXE/iPXE](https://www.linkedin.com/pulse/kubernetes-homelab-part-2-automating-proxmox-pxe-abdulmagomedov-fieqe/), we automated the installation of Proxmox VE on three physical machines.

At this point, we have three Proxmox servers running, but we still don't have a Kubernetes cluster.

The next challenge is to configure those servers, create the virtual machines, prepare their operating systems, and install Kubernetes.

We could do much of this manually through the Proxmox web interface and SSH. However, my goal for this homelab is to learn how to manage infrastructure through code, rather than repeat the same installation steps every time.

For this part, we will use **Ansible** and **Terraform** to automate the remaining setup.

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

We will complete the setup in four stages:

1. **Ansible:** Configure Proxmox hosts, create a Proxmox cluster, and prepare an Ubuntu VM template.

2. **Terraform:** Provision six Ubuntu virtual machines.

3. **Ansible:** Configure Ubuntu on all six virtual machines.

4. **Ansible:** Install Kubernetes, configure networking, and validate the cluster.


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

With the virtual machines running, the next step is preparing their operating systems.

---

## Step 3: Configure Ubuntu with Ansible

Our six Ubuntu virtual machines are now running, but they still need some general configuration before we install Kubernetes.

We could connect to each VM individually and run the same commands. Instead, we will let Ansible handle the work.

This phase is separate from Kubernetes installation because these settings are useful for managing Ubuntu itself.

### Step 3.1: Configure the Kubernetes Inventory

The inventory is located at:

```
ubuntu-config/inventory/hosts.ini
```

It divides our virtual machines into two groups:

```
[control_plane]
control-plane-01 ansible_host=192.168.8.31

[workers]
worker-01 ansible_host=192.168.8.32
worker-02 ansible_host=192.168.8.33
worker-03 ansible_host=192.168.8.34
worker-04 ansible_host=192.168.8.35
worker-05 ansible_host=192.168.8.36

[kubernetes:children]
control_plane
workers

[kubernetes:vars]
ansible_user=ubuntu
ansible_become=true
ansible_python_interpreter=/usr/bin/python3.12
```

Notice that we created a parent group called `[kubernetes:children]`.

This allows us to run tasks against all six VMs using the `kubernetes` group, while still targeting the control plane or workers separately when needed.

### Step 3.2: Review Ubuntu Configuration

The playbook is:

```
ubuntu-config/configure-ubuntu.yaml
```

The playbook handles the following Ubuntu configuration steps.

### Step 3.3: Configure Host Resolution

Each VM receives entries for the other nodes in `/etc/hosts`, allowing us to use hostnames such as `worker-01` instead of remembering every IP address.

### Step 3.4: Upgrade Ubuntu Packages

Ansible updates installed packages and reboots the VMs when Ubuntu indicates a reboot is required.

### Step 3.5: Configure Time Synchronization

The playbook enables NTP (Network Time Protocol), which helps keep the machines' system clocks synchronized.

### Step 3.6: Configure Console Authentication

We configure a local password for the `ubuntu` account so we can log in through the Proxmox web console when SSH isn't available.

For security, the real password hash is not stored in GitHub.

The repository includes a sample file:

```
ubuntu-config/vars/credentials.example.yaml
```

Create a private copy:

```
cp ubuntu-config/vars/credentials.example.yaml \
   ubuntu-config/vars/credentials.yaml
```

Generate a password hash:

```
openssl passwd -6
```

Copy the generated hash into `credentials.yaml`, replacing the example value.

The real credentials file is ignored by Git.

SSH key authentication remains available independently from the console password.

### Step 3.7: Run the Ubuntu Playbook

```
ansible-playbook \
  -i ubuntu-config/inventory/hosts.ini \
  ubuntu-config/configure-ubuntu.yaml
```

When this finishes, all six virtual machines should have consistent Ubuntu configuration.

**Verify Step 3**

Test Ansible connectivity to all VMs:

```
ansible kubernetes \
  -i ubuntu-config/inventory/hosts.ini \
  -m ansible.builtin.ping
```

On a VM, check time synchronization:

```
timedatectl status
```


Our Ubuntu machines are ready. Now we can finally install Kubernetes.

---

## Step 4: Install Kubernetes with Ansible

This is the final and largest stage of our homelab setup.

We already have six Ubuntu virtual machines with consistent system configuration. Now we need to turn them into a functioning Kubernetes cluster.

The Kubernetes playbook is located at:

```
kubernetes-config/configure-kubernetes.yaml
```

This file contains the installation steps for the control plane, workers, container runtime, Helm, and Cilium networking.

We also keep our software versions in:

```
kubernetes-config/group_vars/kubernetes.yaml
```

The repository's configuration uses Kubernetes 1.37, Helm v3.19.0, and Cilium 1.20.4.

### Step 4.1: Prepare Ubuntu for Kubernetes

Kubernetes requires some additional Linux configuration before we can initialize the cluster.

Our Ansible playbook disables swap and enables IPv4 packet forwarding.

**Swap** allows Linux to use disk space as an extension of RAM. For this kubeadm-based setup, we disable it to keep the node configuration simple and compatible with our kubelet settings.

**IPv4 packet forwarding** allows the Linux kernel to forward network traffic between interfaces. This is important for our Kubernetes networking.

The playbook applies these settings across all six VMs.

### Step 4.2: Install the Container Runtime

Kubernetes manages containers, but it does not run them directly.

It needs a **container runtime**, which is the software responsible for starting and managing containers on a node.

We will use **containerd**.

Ansible installs containerd from Docker's APT repository, generates its configuration, and enables the `systemd` cgroup driver.

The playbook also holds the containerd package version to avoid unintended upgrades during routine package updates.

One useful thing to understand here is that we do not need to install the full Docker Engine to run Kubernetes.

Containerd provides the runtime functionality Kubernetes needs.

### Step 4.3: Install Kubernetes Components

Next, we install three Kubernetes tools:

|Component|Purpose|
|---|---|
|`kubeadm`|Initializes a Kubernetes cluster and joins nodes|
|`kubelet`|Runs on each node and manages Pods assigned to it|
|`kubectl`|Command-line tool used to communicate with Kubernetes|

Ansible configures the Kubernetes APT repository, installs these packages, and holds their versions to prevent unexpected upgrades.

At this stage, the software is installed, but we still haven't created the Kubernetes cluster.

### Step 4.4: Initialize the Control Plane

Now we are ready to create our control plane.

Kubeadm provides a command for this:

```
kubeadm init
```

Our Ansible playbook runs that command on `control-plane-01`.

The relevant task is simple:

```
- name: Initialize control plane with kubeadm
  ansible.builtin.command:
    cmd: kubeadm init
    creates: /etc/kubernetes/admin.conf
  no_log: true
```

Notice `creates: /etc/kubernetes/admin.conf`.

Ansible checks whether that file already exists before executing the command. This helps prevent a normal playbook rerun from trying to initialize the same control plane again.

After initialization, kubeadm creates the Kubernetes configuration file used to communicate with the cluster.

Our playbook copies it to:

```
/home/ubuntu/.kube/config
```

This gives the `ubuntu` account access to administer Kubernetes using `kubectl`.

We can now run commands such as:

```
kubectl get nodes
```

The control plane should appear in the output.

It may initially show `NotReady`, which is expected before we finish configuring Pod networking.

### Step 4.5: Join the Worker Nodes

The control plane is running, but it still needs worker nodes.

Kubeadm generates a join command containing the information each worker needs to connect to the cluster.

Our Ansible playbook generates this command on the control plane and passes it to the five workers.

Each worker then executes the join command automatically.

We don't need to copy and paste the command into each VM.

The playbook also checks for `/etc/kubernetes/kubelet.conf` before running the join command. If that file already exists, Ansible skips the join operation for that worker.

Once the workers have joined, we should see six nodes when running:

```
kubectl get nodes -o wide
```

One control plane and five workers.

However, Kubernetes still needs a networking solution before the cluster is fully operational.

### Step 4.6: Install Helm

Before installing our networking component, we will install **Helm**.

Helm is a package manager for Kubernetes.

It allows us to install applications and Kubernetes components using reusable packages called **charts**.

Without Helm, we might need to manage many individual Kubernetes YAML manifests for more complex software.

Helm simplifies that process by packaging the required Kubernetes resources together.

Our Ansible playbook installs Helm on the control-plane VM.

We can verify it with:

```
helm version
```

### Step 4.7: Install Cilium Networking

Kubernetes needs a **Container Network Interface (CNI)** plugin to provide networking for Pods.

For this homelab, we selected **Cilium**.

Cilium provides networking between Pods and nodes, and it supports additional networking and security capabilities that we can explore as we learn more about Kubernetes.

Our Ansible playbook installs Cilium using its Helm chart.

In simplified terms, this is the operation Ansible performs:

```
helm upgrade --install cilium \
  oci://quay.io/cilium/charts/cilium \
  --version 1.20.4 \
  --namespace kube-system \
  --wait \
  --timeout 10m
```

The `--install` option tells Helm to install the release if it doesn't exist.

The `--wait` option makes Helm wait for the relevant Kubernetes resources to become ready, up to the specified timeout.

Cilium manages Pod IP address allocation in this setup. Each Kubernetes node receives a Pod address range that is separate from our physical homelab network.

After Cilium is installed and healthy, our Kubernetes nodes should transition to `Ready`.

We can verify Cilium using:

```
kubectl -n kube-system get daemonset cilium
```

In our six-node cluster, the Cilium DaemonSet should report six ready agents.

We can also check the address ranges assigned to the nodes:

```
kubectl get ciliumnodes \
  -o custom-columns=NAME:.metadata.name,POD-CIDRS:.spec.ipam.podCIDRs
```

In my homelab, Cilium allocated Pod subnets in the `10.0.x.0/24` range.

The exact subnet assignments may vary between installations.

### Step 4.8: Configure kubectl Shortcuts

Once the cluster is working, we can make day-to-day administration a little easier.

Instead of typing `kubectl` every time, I wanted a shorter command:

```
k get nodes
```

Our Ansible playbook configures the Bash alias:

```
alias k=kubectl
```

It also installs Bash completion so we can use the Tab key when typing Kubernetes commands.

These settings are applied to all six Ubuntu VMs.

One important distinction: although the alias is installed on every node, the Kubernetes administration configuration is only copied to the control-plane VM.

The workers don't automatically receive the cluster administrator's credentials.

### Step 4.9: Run a Kubernetes Smoke Test

The last step is to check whether Kubernetes can deploy and run a container.

This is called a **smoke test**.

A smoke test is a quick way to verify that the most important parts of a system are working before moving on to more detailed testing.

For our cluster, the test performs four operations:

1. Creates a temporary NGINX Pod.

2. Waits for the Pod to become `Ready`.

3. Displays the Pod and the node it was scheduled on.

4. Deletes the temporary Pod.


This verifies that Kubernetes can accept a request, schedule a workload, download a container image, and start the container.

The Ansible playbook uses an `always` block to attempt cleanup even if the test fails.

I also added an Ansible tag called `smoke-test`.

This means we can run the final test without repeating the entire Kubernetes installation:

```
ansible-playbook \
  -i ubuntu-config/inventory/hosts.ini \
  kubernetes-config/configure-kubernetes.yaml \
  --tags smoke-test
```

For an additional check on the control plane:

```
kubectl get pod nginx-test --ignore-not-found
```

If the cleanup succeeded, the command should return no Pod.

This does not test every Kubernetes networking feature, but it gives us a useful first confirmation that the cluster can run a workload.

### Run the Kubernetes Playbook

We have covered what each Kubernetes stage does.

The complete installation is automated through one playbook:

```
ansible-playbook \
  -i ubuntu-config/inventory/hosts.ini \
  kubernetes-config/configure-kubernetes.yaml
```

Run this after the Ubuntu configuration stage is complete.

The playbook prepares the nodes, installs Kubernetes, initializes the control plane, joins the workers, installs Helm and Cilium, configures the shell shortcuts, and runs the temporary NGINX test.


---

## Final Verification

At this point, all four stages are complete.

We should have three physical Proxmox servers hosting six Ubuntu virtual machines, with Kubernetes installed and configured across all six.

On the control-plane VM, run:

```
kubectl get nodes -o wide
```

We should see:

```
control-plane-01   Ready   control-plane
worker-01          Ready   <none>
worker-02          Ready   <none>
worker-03          Ready   <none>
worker-04          Ready   <none>
worker-05          Ready   <none>
```

The actual output also includes information such as node age, Kubernetes version, and IP address.

Next, check the workloads running across the cluster:

```
kubectl get pods -A
```

Finally, check the installed Helm releases:

```
helm list -A
```

We should see our Cilium release in the `kube-system` namespace.


## What Did We Accomplish?

Let's look at where we started.

In Part 1, we connected three physical computers to a dedicated network.

In Part 2, we automated Proxmox installation using PXE, iPXE, and a reusable installer.

In this part, we automated almost everything that came after the operating system installation.

We configured and clustered the Proxmox servers, prepared an Ubuntu template, created six virtual machines with Terraform, configured their operating systems with Ansible, and installed a working Kubernetes cluster.

More importantly, we now have the configuration saved as code.

If we need to recreate part of our environment, we have a documented and repeatable starting point instead of relying on memory or screenshots of manual configuration.

This doesn't mean every action is perfectly repeatable under every condition. Cluster initialization, upgrades, credentials, and Terraform state still need care. But it is a significant improvement over performing the entire setup manually.

## Wrap-Up

One of the biggest lessons from this project has been understanding how different tools work together.

Before building this homelab, it was easy to view Proxmox, Terraform, Ansible, and Kubernetes as separate technologies.

Working through the installation helped me understand how they fit into one infrastructure workflow:

**Proxmox** provides the virtualization platform.

**Terraform** provisions the virtual machines.

**Ansible** prepares the operating systems and installs Kubernetes.

**Kubernetes** manages the containerized workloads.

And **Helm and Cilium** provide important capabilities within the cluster.

Along the way, I also learned why testing each stage matters. When something fails, it is much easier to troubleshoot a specific configuration step than to investigate the entire environment at once.

The goal of this series has never been to build the largest or most complicated homelab. It has been to understand the technologies by building something practical, one step at a time.

If you are working on a similar project, feel free to explore the repository, reuse the configuration, and adapt it to your hardware.

**GitHub:** [Homelab Proxmox IaC](https://github.com/nekrorat/homelab-proxmox-iac)


Thanks for following along with my Kubernetes Homelab series. I hope this walkthrough helps make Infrastructure as Code and Kubernetes a little more approachable for anyone getting started.

I welcome recommendations and suggestions from others who have built similar environments.

#Kubernetes #Homelab #DevOps #Ansible #Terraform #Proxmox #InfrastructureAsCode