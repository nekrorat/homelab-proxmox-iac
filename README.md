# homelab-proxmox-iac


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