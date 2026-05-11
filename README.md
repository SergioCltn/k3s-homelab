# k3s Ansible Setup

This project manages a single-node `k3s` cluster with Ansible.

Default target:

- Host: `aetherion@192.168.1.134`
- Mode: single-node server with embedded `etcd`
- Disabled addons: `traefik`, `servicelb`

## Layout

- `inventory/hosts.yml`: target hosts and SSH settings
- `group_vars/k3s.yml`: cluster settings
- `playbooks/install.yml`: install `k3s` and fetch kubeconfig
- `playbooks/status.yml`: inspect cluster state
- `playbooks/uninstall.yml`: remove `k3s`

## Requirements

- `ansible` installed locally
- SSH key access to `aetherion@192.168.1.134`
- `sudo` on the remote host

## Configuration

Update these files as needed:

- `inventory/hosts.yml`
- `group_vars/k3s.yml`

Main variables:

- `k3s_channel`
- `k3s_install_exec`
- `k3s_server_config`
- `k3s_update_system`
- `k3s_kubeconfig_dir`
- `k3s_kubeconfig_name`

## Usage

Install the cluster:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/install.yml
```

Check status:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/status.yml
```

Uninstall the cluster:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/uninstall.yml
```

Use the fetched kubeconfig locally:

```bash
KUBECONFIG=./kubeconfig/aetherion.yaml kubectl get nodes
```

## Optional Helm Addons

Console-driven Helm setup files are in `helm/`.

Layout:

- `helm/platform/`: shared cluster services and Helm values
- `helm/access/`: public access and Cloudflare-related manifests
- `helm/apps/pi-hole/`: local DNS service for LAN hostname rewrites
- `helm/apps/gitea/`: self-hosted Git service resources
- `helm/apps/registry/`: in-cluster Docker registry resources
- `helm/apps/spend-app/`: real application resources
- `helm/examples/spendapp/`: old dummy example app used for ingress validation
- `helm/README.md`: step-by-step install and verification commands

Important files:

- `helm/platform/metallb-values.yaml`
- `helm/platform/metallb-ipaddresspool.yaml`
- `helm/platform/ingress-nginx-values.yaml`
- `helm/platform/cert-manager-values.yaml`
- `helm/platform/clusterissuer-letsencrypt-production.yaml`
- `helm/platform/external-dns-namespace.yaml`
- `helm/platform/external-dns.yaml`
- `helm/platform/external-dns-pihole.secret.yaml.example`
- `helm/platform/argocd-values.yaml`
- `helm/platform/argocd-server-ingress.yaml`
- `helm/platform/argocd-application-spend-app.yaml`
- `helm/platform/argocd-app-of-apps.yaml`
- `helm/platform/argocd-apps/`
- `helm/apps/gitea/kustomization.yaml`
- `helm/apps/pi-hole/kustomization.yaml`
- `helm/apps/registry/kustomization.yaml`
- `helm/access/cloudflared-deployment.yaml`
- `helm/apps/pi-hole/namespace.yaml`
- `helm/apps/pi-hole/pi-hole.yaml`
- `helm/apps/pi-hole/web-password.secret.yaml.example`
- `helm/apps/gitea/namespace.yaml`
- `helm/apps/gitea/gitea.yaml`
- `helm/apps/gitea/actions-runner-token.secret.yaml.example`
- `helm/apps/gitea/actions-runner.yaml`
- `helm/apps/gitea/actions-buildkit.yaml`
- `helm/apps/registry/namespace.yaml`
- `helm/apps/registry/registry.yaml`
- `helm/apps/spend-app/namespace.yaml`
- `helm/apps/spend-app/postgres.yaml`
- `helm/apps/spend-app/backend.yaml`
- `helm/apps/spend-app/ingress.yaml`

These install:

- MetalLB with address pool `192.168.1.240-192.168.1.250`
- `ingress-nginx` exposed through a `LoadBalancer` service for LAN access
- `cert-manager` with Cloudflare DNS challenge for Let's Encrypt
- `external-dns` for automatic LAN DNS records in Pi-hole
- `Argo CD` for GitOps-style reconciliation on the LAN
- `cloudflared` tunnel support for public access behind CGNAT
- `Pi-hole` for local DNS overrides on the LAN
- `Gitea` for local Git hosting on the LAN
- in-cluster Gitea Actions runner with BuildKit-based image builds
- in-cluster Docker registry for local image pushes and pod pulls
- `spend-app` backend and PostgreSQL manifests

For this host's current 5G connection, the router WAN is behind CGNAT, so the recommended public access path is the Cloudflare Tunnel setup in `helm/README.md`, not router port forwarding.

Current public routing:

- `https://spendapp.sergiocltn.com` -> Cloudflare Tunnel -> `ingress-nginx` -> `spend-app-backend`

Current LAN-only hostname:

- `http://spendapp.home.arpa` -> Pi-hole DNS record -> `ingress-nginx` -> `spend-app-backend`

Use the commands in `helm/README.md` to install and verify them.

## What happens during install

- Updates the Debian system packages first
- Writes a managed `/etc/rancher/k3s/config.yaml`
- Runs the official `k3s` installer on the remote host
- Restarts `k3s` when the managed config changes
- Enables and starts `k3s`
- Waits for `/readyz`
- Reads `/etc/rancher/k3s/k3s.yaml`
- Rewrites `127.0.0.1` to the host IP
- Writes the kubeconfig into `./kubeconfig/`
