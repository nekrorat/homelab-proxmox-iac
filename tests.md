# Homelab verification commands

This guide collects commands for checking the milestones implemented by this repository. Use it **independently from the articles** whenever you need to verify one step or troubleshoot an existing installation.

For full setup instructions, see [README.md](README.md).

> **Where to run commands**
>
> - Commands labeled **management machine** run on the computer where you cloned this repository.
> - Commands labeled **Proxmox host** run in a root shell on the relevant physical host.
> - Commands labeled **control plane** run as the `ubuntu` user on `control-plane-01`, unless indicated otherwise.
> - Commands labeled **worker** run on the relevant Ubuntu worker VM.
>
> Unless noted as **mutating**, checks below only inspect state. Replace example IPs and hostnames if you changed the inventories.

## 0. Local prerequisites and syntax checks

**Management machine**, from the repository root:

```bash
ansible --version
terraform version
ansible-galaxy collection list ansible.posix
ssh -V
```

Expected: installed Ansible and Terraform, with the `ansible.posix` collection available.

Check inventories and target groups:

```bash
ansible-inventory -i proxmox-config/inventory/hosts.ini --graph
ansible-inventory -i ubuntu-config/inventory/hosts.ini --graph
```

Expected: `pve01`–`pve03` in the first inventory, and one `control_plane` plus five `workers` in the second.

Check Ansible playbook syntax without applying anything:

```bash
ansible-playbook --syntax-check \
  -i proxmox-config/inventory/hosts.ini \
  proxmox-config/configure-proxmox.yaml

ansible-playbook --syntax-check \
  -i ubuntu-config/inventory/hosts.ini \
  ubuntu-config/configure-ubuntu.yaml

ansible-playbook --syntax-check \
  -i ubuntu-config/inventory/hosts.ini \
  kubernetes-config/configure-kubernetes.yaml
```

**Note:** The Ubuntu syntax check can require the local `ubuntu-config/vars/credentials.yaml` referenced by the playbook. Copy and populate the credentials example as explained in the README.

## 1. Proxmox configuration with Ansible

### Step 1.1: Prepare the Repository

Run the local prerequisite and syntax checks in [Section 0](#0-local-prerequisites-and-syntax-checks) before connecting to the Proxmox hosts.


### Step 1.2: Configure the Ansible Inventory

The first SSH test also verifies the Proxmox hosts listed in the Ansible inventory.


**Management machine:**

```bash
ansible proxmox -i proxmox-config/inventory/hosts.ini -m ansible.builtin.ping
ssh root@192.168.8.21
ssh root@192.168.8.22
ssh root@192.168.8.23
```

Expected: `pong` for all three hosts and SSH access to the intended Proxmox hosts. Exit each SSH shell before the next command.

### Step 1.3: Review the Proxmox Playbook

Check the Proxmox playbook syntax using the command in [Section 0](#0-local-prerequisites-and-syntax-checks).

### Step 1.4: Configure Proxmox Package Repositories

**Proxmox host:**

```bash
grep -R 'pve-no-subscription' /etc/apt/sources.list.d/
apt-cache policy pve-manager
```

Expected: the no-subscription repository is configured. Enterprise repository files should not be enabled by the Ansible playbook.

### Step 1.5: Remove the Subscription Reminder (Optional)

**Proxmox host:**

```bash
ls -l /usr/local/bin/remove-proxmox-subscription-nag
cat /etc/apt/apt.conf.d/no-nag-script
```

Expected: both files exist if you ran the complete Proxmox playbook. The customization is optional and not required for Kubernetes.

### Step 1.6: Upgrade Proxmox Packages

**Proxmox host:**

```bash
test ! -e /var/run/reboot-required && echo 'No reboot required'
apt list --upgradable
```

Expected: after any required reboot, the reboot-required flag is absent. New package updates may appear later.

### Step 1.7: Configure Hostnames and Name Resolution

**Proxmox host:**

```bash
hostname
getent hosts pve01 pve02 pve03
```

Expected: the correct hostname and all three hosts resolving to their configured IP addresses.

### Step 1.8: Verify Proxmox Host Connectivity

**Proxmox host:**

```bash
hostname
getent hosts pve01 pve02 pve03
ping -c 1 pve01
ping -c 1 pve02
ping -c 1 pve03
systemctl is-active pveproxy
```

Expected: correct host identity, resolution to `192.168.8.21`–`.23`, successful ping replies, and `active` for `pveproxy`. The exact addresses depend on your inventory.

### Step 1.9: Create the Proxmox Cluster

**Proxmox host:**

```bash
pvecm status
pvecm nodes
test -f /etc/pve/corosync.conf && echo 'Cluster configuration present'
```

Expected: cluster name `homelab`, three nodes, and quorate cluster status once all nodes have joined.

### Step 1.10: Create Terraform API Access

**Management machine:**

```bash
test -f proxmox-config/terraform-api-token.env && echo 'Local token file exists'
source proxmox-config/terraform-api-token.env
test -n "$PROXMOX_VE_ENDPOINT" && echo 'Endpoint loaded'
test -n "$PROXMOX_VE_API_TOKEN" && echo 'Token loaded'
```

Expected: all three success messages. These commands intentionally **do not print the token**.

**Proxmox host `pve01`:**

```bash
pveum user token list root@pam
```

Expected: token named `terraform`. Listing a token does **not** reveal its secret. If the local token file is missing, retrieve credentials from your secure backup or deliberately rotate the token before using Terraform.

### Step 1.11: Prepare the Ubuntu Cloud-Init Template

**Proxmox host `pve01`:**

```bash
qm list
qm config 9000
qm config 9000 | grep -E 'template:|scsi0:|ide2:|boot:|serial0:'
```

Expected: VM `9000` is a template, with the imported Ubuntu disk and Cloud-Init drive present.

### Step 1.12: Run the Proxmox Playbook

After running `proxmox-config/configure-proxmox.yaml`, verify the repository, host connectivity, cluster status, API token, and template using Steps 1.4–1.11 above.

## 2. Terraform provisioning

### Step 2.1: Define the Virtual Machines

Review `vm-provision/variables.tf` for all six VM names, VM IDs, host placement, IPs, memory, storage, and the SSH public-key path. Check for conflicts before deploying. This is a configuration review rather than a runtime test.


All commands in this section run on the **management machine**. Load your Proxmox API token environment before using the provider:

```bash
source proxmox-config/terraform-api-token.env
```

### Step 2.2: Test Terraform's Proxmox Connection (Optional)

This repository includes a separate test directory that reads the available Proxmox node names:

```bash
terraform -chdir=vm-provision/tests/connection init
terraform -chdir=vm-provision/tests/connection validate
terraform -chdir=vm-provision/tests/connection plan
terraform -chdir=vm-provision/tests/connection apply
terraform -chdir=vm-provision/tests/connection output proxmox_nodes
```

Expected: the output contains the Proxmox nodes, including `pve01`, `pve02`, and `pve03`. This test reads provider data but still writes its own Terraform state.

### Step 2.3: Test the Ubuntu Template Clone (Optional)

**Mutating test:** `vm-provision/tests/vm-clone` creates **VM 100** named `ubuntu-test` at `192.168.8.37` on `pve01`. Confirm the VM ID and IP are unused before running this test.

```bash
terraform -chdir=vm-provision/tests/vm-clone init
terraform -chdir=vm-provision/tests/vm-clone validate
terraform -chdir=vm-provision/tests/vm-clone plan
terraform -chdir=vm-provision/tests/vm-clone apply
```

Expected: the test VM can be cloned from template 9000 and starts.

Verify the optional test VM:

```bash
ssh ubuntu@192.168.8.37
```

After logging out, **destroy only the optional test** from its own directory:

```bash
terraform -chdir=vm-provision/tests/vm-clone destroy
```

Do **not** run the destroy command in `vm-provision/`, which manages your real Kubernetes VMs.

### Step 2.4: Initialize and Deploy

```bash
terraform -chdir=vm-provision init
terraform -chdir=vm-provision fmt -check
terraform -chdir=vm-provision validate
terraform -chdir=vm-provision plan
```

Expected: validation succeeds. On a first deployment, the plan shows **six VMs to add**. After a successful deployment with unchanged configuration, expect **no changes**. Investigate any unexpected VM replacements.

### Step 2.5: Verify the Virtual Machines

```bash
terraform -chdir=vm-provision state list
terraform -chdir=vm-provision output kubernetes_vms
```

Expected: six instances under `proxmox_virtual_environment_vm.kubernetes` and output containing the expected VM IDs, Proxmox nodes, and IPs.

From a Proxmox host, check the corresponding VMs:

```bash
qm list
qm config 101
```

Check access to each Ubuntu VM from the management machine:

```bash
for ip in 192.168.8.31 192.168.8.32 192.168.8.33 192.168.8.34 192.168.8.35 192.168.8.36; do
  ssh -o BatchMode=yes -o ConnectTimeout=5 "ubuntu@$ip" hostname
done
```

Expected: all six hostnames. If Cloud-Init is still running, wait on the relevant VM:

```bash
ssh ubuntu@192.168.8.31 'cloud-init status --wait'
```

## 3. General Ubuntu configuration

### Step 3.2: Review Ubuntu Configuration

Check that `ubuntu-config/configure-ubuntu.yaml` contains the host resolution, update, time synchronization, and console authentication tasks. Verify that your local `ubuntu-config/vars/credentials.yaml` exists without printing its contents.


### Step 3.1: Configure the Kubernetes Inventory

**Management machine:**

```bash
ansible-inventory -i ubuntu-config/inventory/hosts.ini --graph
ansible kubernetes -i ubuntu-config/inventory/hosts.ini -m ansible.builtin.ping
```

Expected: one control plane, five workers, and successful connectivity.

### Step 3.3: Configure Host Resolution

**Management machine:**

```bash
ansible kubernetes -i ubuntu-config/inventory/hosts.ini -m ansible.builtin.ping
```

Expected: `pong` from all six VMs.

**Any Ubuntu VM:**

```bash
hostname
getent hosts control-plane-01 worker-01 worker-02 worker-03 worker-04 worker-05
cat /etc/hosts
```

Expected: six entries matching the Ubuntu inventory.

### Step 3.4: Upgrade Ubuntu Packages

**Ubuntu VM:**

```bash
apt list --upgradable
test ! -e /var/run/reboot-required && echo 'No reboot required'
```

Expected: the second line prints its success message after any required reboot. The upgradeable-package list may legitimately contain packages released after the playbook last ran.

### Step 3.5: Configure Time Synchronization

**Ubuntu VM:**

```bash
timedatectl status
timedatectl show -p NTP -p NTPSynchronized
```

Expected: NTP enabled. `NTPSynchronized=yes` may take time after first boot if a time source is not yet reachable.

### Step 3.6: Configure Console Authentication

The playbook configures a local password for `ubuntu` to use with the Proxmox noVNC console. Open a VM's **Console** in the Proxmox web UI and log in as `ubuntu` using the password you configured in `ubuntu-config/vars/credentials.yaml`.

Do not print password hashes in shared command output, screenshots, or issue reports.

### Step 3.7: Run the Ubuntu Playbook

After running `ubuntu-config/configure-ubuntu.yaml`, verify Ansible connectivity, host resolution, reboot status, NTP, and console login using Steps 3.1–3.6 above.

## 4. Kubernetes installation and runtime

Unless noted otherwise, Kubernetes node checks run on **each Ubuntu VM** and cluster checks run as `ubuntu` on **control-plane-01**.

### Step 4.1: Prepare Ubuntu for Kubernetes

**Each Ubuntu VM:**

```bash
swapon --show
cat /proc/sys/net/ipv4/ip_forward
sysctl net.ipv4.ip_forward
grep -E '^[^#].*[[:space:]]swap[[:space:]]' /etc/fstab || true
```

Expected: no active swap devices, IPv4 forwarding is `1`, and no uncommented swap mount entries in `/etc/fstab`.

### Step 4.2: Install the Container Runtime

**Each Ubuntu VM:**

```bash
containerd --version
systemctl is-active containerd
systemctl is-enabled containerd
grep 'SystemdCgroup = true' /etc/containerd/config.toml
sudo ctr plugins ls
```

Expected: containerd installed and running, enabled at startup, with `SystemdCgroup = true` in the configuration. The plugin listing helps troubleshoot runtime initialization problems. It is not a full Kubernetes health check.

Check the installed Debian package:

```bash
dpkg-query -W containerd.io
```

### Step 4.3: Install Kubernetes Components

**Each Ubuntu VM:**

```bash
kubeadm version
kubelet --version
kubectl version --client
dpkg-query -W kubeadm kubelet kubectl
apt-mark showhold
systemctl is-enabled kubelet
systemctl is-active kubelet
```

Expected: the intended Kubernetes minor version and `kubeadm`, `kubelet`, `kubectl` in the APT hold list. The kubelet may fail or restart **before** the node is initialized or joined. After the complete cluster setup it should be active.

### Step 4.4: Initialize the Control Plane

**Control plane:**

```bash
sudo test -f /etc/kubernetes/admin.conf && echo 'kubeadm initialized'
test -f ~/.kube/config && echo 'kubectl configured'
kubectl cluster-info
kubectl get nodes -o wide
sudo systemctl is-active kubelet
```

Expected: both files exist, cluster-info reports an API server, and the control-plane node appears in `kubectl get nodes`. If networking is not installed yet, a node may initially appear `NotReady`.

If an Ansible-executed `kubectl` command instead connects to `localhost:8080`, test explicitly:

```bash
KUBECONFIG=/home/ubuntu/.kube/config kubectl get nodes
```

### Step 4.5: Join the Worker Nodes

**Control plane:**

```bash
kubectl get nodes -o wide
kubectl get nodes --no-headers
```

Expected: **six nodes**, one control plane and five workers. A worker may be temporarily `NotReady` until its networking is configured.

**Each worker:**

```bash
sudo test -f /etc/kubernetes/kubelet.conf && echo 'Worker has joined configuration'
sudo systemctl is-active kubelet
```

Expected: the kubelet configuration exists and kubelet is active. The existence of this file confirms the local join configuration, not overall cluster health.

Optional, **control plane**:

```bash
sudo kubeadm token list
```

This lists bootstrap tokens and expiration timestamps. **The setup playbook generates a new bootstrap token on each full run**, but joined workers are protected by the Ansible `creates` guard.

### Step 4.6: Install Helm

**Control plane:**

```bash
helm version
command -v helm
```

Expected: Helm is installed at `/usr/local/bin/helm` with the version currently installed on that VM.

### Step 4.7: Install Cilium Networking

**Control plane:**

```bash
helm list -n kube-system
helm status cilium -n kube-system
kubectl -n kube-system get daemonset cilium
kubectl -n kube-system get deployments
kubectl -n kube-system get pods -o wide
kubectl get nodes
```

Expected: the Cilium release is deployed, the Cilium DaemonSet is ready on all six nodes, the operator has ready replicas, and all six Kubernetes nodes eventually report `Ready`.

**Cilium pod CIDR checks:**

```bash
kubectl get ciliumnodes
kubectl get ciliumnodes -o custom-columns=NAME:.metadata.name,POD-CIDRS:.spec.ipam.podCIDRs
```

Expected: a distinct Pod address range assigned to each node. In the example environment, the observed allocations were six `10.0.x.0/24` ranges. The assignment order can change between installations.

Cilium is configured with cluster-pool IPAM, so `kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}'` may return empty values. Use `CiliumNode.spec.ipam.podCIDRs` for this setup.

**Cluster DNS sanity check:**

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system get service kube-dns
```

Expected: CoreDNS Pods running and the kube-dns Service present. This is a readiness check, **not** a full DNS query test.

### Step 4.8: Configure kubectl Shortcuts

Open a **new interactive Bash shell** on an Ubuntu VM, or run `source ~/.bashrc`:

```bash
alias k
type __start_kubectl
complete -p k
```

Expected: `k` expands to `kubectl` and its Bash completion function is registered. Press **Tab** after a partial `k` command to test completion. Completion is set up on workers too, but the administrative kubeconfig is only installed on the control plane.

### Step 4.9: Run a Kubernetes Smoke Test

**Recommended: management machine.** The published playbook marks this play with `smoke-test`:

```bash
ansible-playbook \
  -i ubuntu-config/inventory/hosts.ini \
  kubernetes-config/configure-kubernetes.yaml \
  --tags smoke-test
```

Expected: Ansible creates `nginx-test`, waits for the Pod to be `Ready`, prints the node and Pod information, and deletes the temporary Pod in its `always` block.

Confirm cleanup on the control plane:

```bash
kubectl get pod nginx-test --ignore-not-found
```

Expected: **no Pod returned**. An empty result is the success state.

If you want to perform the same **mutating** test manually on the control plane, run:

```bash
kubectl run nginx-test --image=nginx:stable --restart=Never
kubectl wait --for=condition=Ready pod/nginx-test --timeout=120s
kubectl get pod nginx-test -o wide
kubectl delete pod nginx-test --ignore-not-found=true --wait=true
```

**Important:** If a manual command fails, remember to run the cleanup command yourself. The manual sequence cannot guarantee cleanup after an interrupted shell.

If readiness fails, collect diagnostics **before deleting the Pod**:

```bash
kubectl get pod nginx-test -o wide
kubectl describe pod nginx-test
kubectl logs nginx-test
kubectl get events --sort-by=.lastTimestamp
kubectl delete pod nginx-test --ignore-not-found=true --wait=true
```

Not all commands will return useful logs if the image never started. The failure information usually appears in the Pod's status and events.

The test validates API access, scheduling, image retrieval, and Pod startup. It **does not** fully test cross-node Pod connectivity or Service routing.

## 5. Final cluster check

**Control plane:**

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl -n kube-system get daemonset cilium
kubectl get ciliumnodes -o custom-columns=NAME:.metadata.name,POD-CIDRS:.spec.ipam.podCIDRs
helm list -A
```

A healthy final result shows:

- Six Kubernetes nodes in `Ready` state
- Expected `kube-system` workloads running, including CoreDNS and Cilium
- Cilium agents ready on six nodes
- One CiliumNode resource per Kubernetes node with an assigned Pod CIDR
- The Cilium Helm release present
- A successful and cleaned-up NGINX smoke test

## 6. Safe debugging reminders

- Use `--syntax-check`, `terraform validate`, `terraform plan`, and read-only cluster queries before repeating an installation step.
- Ansible `--start-at-task` runs the matching task **and subsequent tasks**, so it is not the same as selecting one play. The only play-level tag currently configured in this repository is `smoke-test`.
- Avoid printing `terraform-api-token.env` or `credentials.yaml` in terminal transcripts and screenshots.
- Keep each Terraform test directory's state separate. Never use `terraform destroy` in the main `vm-provision` directory to clean up `vm-clone`.
- A full Kubernetes playbook rerun is not a version-upgrade strategy. Check cluster health and the exact versions before changing containerd, kubeadm, Helm, or Cilium.
