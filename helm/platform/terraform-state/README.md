# Terraform State

This app creates the `terraform-state` namespace used by Terraform's Kubernetes backend.

Terraform creates and updates the state Secret itself during `terraform init` and future operations. Do not create the state Secret manually.

Backend example for the Proxmox Terraform repo:

```hcl
terraform {
  backend "kubernetes" {
    namespace        = "terraform-state"
    secret_suffix    = "proxmox-evolution-prod"
    in_cluster_config = false
  }
}
```

After this namespace is synced into the cluster, migrate local state from the Proxmox Terraform repo with:

```sh
terraform init -migrate-state
```

Back up this namespace as part of cluster backups. Losing the state Secret makes Terraform recovery manual and risky.
