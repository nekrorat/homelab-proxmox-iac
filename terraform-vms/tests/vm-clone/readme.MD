Initialize the clone test
`terraform init`
`terraform plan`

Expected:
Plan: 1 to add, 0 to change, 0 to destroy.

`terraform -chdir=proxmox-terraform-vms/tests/vm-clone apply`

Verify SSH access:
`ssh ubuntu@192.168.8.37`

Clean up the test VM
After verifying Ubuntu works, exit the SSH session and run:
`terraform destroy`