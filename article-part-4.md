# Kubernetes Homelab Part 4: Configuring Ubuntu and Installing Kubernetes with Ansible

In [Part 1: Physical Network](https://www.linkedin.com/pulse/kubernetes-homelab-part-1-physical-network-rasul-abdulmagomedov-vafwe/), we built the network for our homelab. In [Part 2: Automating Proxmox Installation with PXE/iPXE](https://www.linkedin.com/pulse/kubernetes-homelab-part-2-automating-proxmox-pxe-abdulmagomedov-fieqe/), we installed Proxmox VE on three physical servers.

In **[Part 3: Automating Proxmox and Provisioning Ubuntu VMs](https://github.com/nekrorat/homelab-proxmox-iac/blob/main/article.md)**, we configured the Proxmox cluster and used Terraform to create six Ubuntu 24.04 virtual machines.

Now it's time to turn those virtual machines into a Kubernetes cluster.

We will complete the remaining two stages:

1. **Step 3:** Configure Ubuntu on all six VMs with Ansible.
2. **Step 4:** Install Kubernetes, connect the workers, configure networking, and validate the cluster.

All the configuration files are in the [Homelab Proxmox IaC repository](https://github.com/nekrorat/homelab-proxmox-iac). You can follow this article without copying individual YAML files because the playbooks are already prepared.

The repository also contains [tests.md](https://github.com/nekrorat/homelab-proxmox-iac/blob/main/tests.md), with verification commands organized by the same step numbers used here. Use it to check individual stages or troubleshoot a failure.

## Before We Begin

You should have completed Steps 1 and 2 from Part 3. That means you have three configured Proxmox hosts, six Ubuntu virtual machines, and SSH access to the VMs from your Management PC.

If you haven't cloned the repository yet, run:

```bash
git clone https://github.com/nekrorat/homelab-proxmox-iac.git
cd homelab-proxmox-iac
```

You will need Ansible, SSH access as the `ubuntu` user, and the `ansible.posix` collection. Check the repository [README](https://github.com/nekrorat/homelab-proxmox-iac/blob/main/README.md) for prerequisites and settings to customize for your own network.

Let's finish our Kubernetes homelab.

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

At this point, all four stages across Parts 3 and 4 are complete.

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

Across Parts 3 and 4, we automated almost everything that came after the physical Proxmox installation.

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