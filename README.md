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
- `playbooks/tailscale.yml`: install Tailscale as a LAN subnet router
- `playbooks/tailscale-disable.yml`: stop Tailscale without uninstalling it
- `playbooks/tailscale-enable.yml`: start an already-authenticated Tailscale node
- `playbooks/shutdown.yml`: cordon k3s, stop it cleanly, and power off the server
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

Most common commands are available through `make`:

```bash
make help
make status
make nodes
make pods
make apps
make top
```

Install or reconcile the cluster:

```bash
make install
```

Manage Tailscale:

```bash
make tailscale AUTH_KEY=tskey-auth-REPLACE_ME
make tailscale-disable
make tailscale-enable
```

Safely shut down the server. This target is guarded and requires the target hostname:

```bash
make shutdown CONFIRM=aetherion
```

Shutdown cordons the single node, stops `k3s` cleanly, syncs pending filesystem writes, and then powers off the host. It does not drain pods because this is a single-node cluster and there is nowhere else to reschedule them.

Run local syntax checks:

```bash
make syntax
```

Raw Ansible commands are still shown below for clarity.

Install the cluster:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/install.yml
```

Check status:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/status.yml
```

Install Tailscale on the server and advertise the LAN subnet:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/tailscale.yml \
  -e tailscale_auth_key=tskey-auth-REPLACE_ME
```

Create the auth key in the Tailscale admin console. Use an ephemeral or reusable auth key with an appropriate expiry for this one host, and do not commit it to Git.

After the playbook runs, approve the advertised route in the Tailscale admin console:

```text
192.168.1.0/24
```

Then connect your laptop or phone to Tailscale and test LAN services through the VPN:

```bash
curl -I http://pi-hole.home.arpa/admin/
curl -I http://git.home.arpa
```

Temporarily disable Tailscale on the server:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/tailscale-disable.yml
```

Enable it again later without a new auth key:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/tailscale-enable.yml
```

Uninstall the cluster. This is guarded and requires explicit confirmation for the target host:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/uninstall.yml \
  -e confirm_uninstall=true \
  -e confirm_target=aetherion
```

When uninstalling agents, the playbook also removes each agent's Kubernetes
Node object from the primary server. If an agent's Kubernetes node name differs
from its inventory hostname, set `k3s_node_name` for that host in the
inventory.

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
- `helm/apps/proxmox/`: LAN-only Proxmox reverse-proxy ingress
- `helm/apps/registry/`: in-cluster Docker registry resources
- `helm/apps/spend-app/`: real application resources
- `helm/examples/spendapp/`: old dummy example app used for ingress validation
- `helm/README.md`: step-by-step install and verification commands

Important files:

- `helm/platform/metallb/`
- `helm/platform/ingress-nginx/`
- `helm/platform/cert-manager/`
- `helm/platform/external-dns/`
- `helm/platform/argocd/`
- `helm/platform/monitoring/`
- `helm/apps/gitea/kustomization.yaml`
- `helm/apps/pi-hole/kustomization.yaml`
- `helm/apps/registry/kustomization.yaml`
- `helm/platform/sealed-secrets/`
- `helm/access/cloudflared-deployment.yaml`
- `helm/apps/pi-hole/namespace.yaml`
- `helm/apps/pi-hole/pi-hole.yaml`
- `helm/apps/pi-hole/pi-hole-web.sealedsecret.yaml`
- `helm/apps/pi-hole/web-password.secret.yaml.example`
- `helm/apps/gitea/namespace.yaml`
- `helm/apps/gitea/gitea.yaml`
- `helm/apps/gitea/actions-runner-token.secret.yaml.example`
- `helm/apps/gitea/actions-runner.yaml`
- `helm/apps/gitea/actions-buildkit.yaml`
- `helm/apps/proxmox/kustomization.yaml`
- `helm/apps/proxmox/proxmox.yaml`
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
- `Sealed Secrets` for Git-safe encrypted Kubernetes secrets
- `Prometheus` and `Grafana` for cluster monitoring on the LAN
- `Gitea` for local Git hosting on the LAN
- Proxmox UI reverse proxy at `proxmox.home.arpa`
- in-cluster Gitea Actions runner with BuildKit-based image builds
- in-cluster Docker registry for local image pushes and pod pulls
- `spend-app` backend and PostgreSQL manifests

For this host's current 5G connection, the router WAN is behind CGNAT, so the recommended public access path is the Cloudflare Tunnel setup in `helm/README.md`, not router port forwarding.

Current public routing:

- `https://spendapp.sergiocltn.com` -> Cloudflare Tunnel -> `ingress-nginx` -> `spend-app-backend`

Current LAN-only hostname:

- `http://spendapp.home.arpa` -> Pi-hole DNS record -> `ingress-nginx` -> `spend-app-backend`
- `https://proxmox.home.arpa` -> Pi-hole DNS record -> `ingress-nginx` -> `192.168.1.45:8006`

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

## Tailscale Subnet Router

The Tailscale playbook is intentionally separate from `playbooks/install.yml`. Running it does not reinstall or restart k3s.

Use `playbooks/tailscale-disable.yml` when you want to temporarily close VPN access while keeping the machine registered in your tailnet. Use `playbooks/tailscale-enable.yml` to start it again. To fully remove the node from Tailscale, delete it from the Tailscale admin console and uninstall the package manually on the server.

Default Tailscale settings live in `group_vars/k3s.yml`:

- `tailscale_advertise_routes`: `192.168.1.0/24`
- `tailscale_accept_dns`: `false`
- `tailscale_ssh`: `true`

Keep `tailscale_accept_dns: false` unless you explicitly want Tailscale to change the server's DNS resolver. For remote clients, configure DNS in the Tailscale admin console if you want `*.home.arpa` names to resolve through Pi-hole while away from home.
