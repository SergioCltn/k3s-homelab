# AGENTS.md

## Project

This repository manages a single-node `k3s` cluster with Ansible.

Default target:

- Host: `aetherion@192.168.1.134`
- Inventory group: `k3s`
- Mode: single-node server with embedded `etcd`
- Disabled addons: `traefik`, `servicelb`
- WAN reality: current 5G router is behind CGNAT, so public exposure should prefer Cloudflare Tunnel over direct port forwarding
- Current public app host: `spendapp.sergiocltn.com` routes through Cloudflare Tunnel to `ingress-nginx`, which routes to the `spend-app` backend service

## Key Files

- `inventory/hosts.yml`: target host and SSH settings
- `group_vars/k3s.yml`: cluster settings and kubeconfig output path
- `playbooks/install.yml`: system update, config management, install/reconcile, kubeconfig fetch
- `playbooks/status.yml`: service and cluster inspection
- `playbooks/uninstall.yml`: cluster removal
- `helm/`: console-driven Helm values and manifests for optional addons
- `README.md`: user-facing usage notes

## Working Rules

- Prefer small, targeted edits.
- Keep this as an Ansible-first project; do not reintroduce shell wrapper scripts unless explicitly requested.
- Preserve the current behavior unless asked otherwise:
  - update the remote Debian system during install
  - manage `/etc/rancher/k3s/config.yaml`
  - disable `traefik` and `servicelb`
  - fetch kubeconfig to `./kubeconfig/aetherion.yaml`
- Treat `install.yml` as both install and reconcile. Changes to managed config should continue to apply cleanly to an already-installed host.
- Do not assume the remote host is reachable; verify with Ansible or SSH-facing commands before claiming remote state.
- Do not remove or overwrite local `kubeconfig/` contents unless explicitly requested.

## Common Commands

Run from the repository root:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/install.yml
ansible-playbook -i inventory/hosts.yml playbooks/status.yml
ansible-playbook -i inventory/hosts.yml playbooks/uninstall.yml
ansible-playbook --syntax-check playbooks/install.yml
```

Use the fetched kubeconfig locally:

```bash
KUBECONFIG=./kubeconfig/aetherion.yaml kubectl get nodes
```

## Editing Guidance

- If you add variables, put them in `group_vars/k3s.yml` unless they are host-specific.
- Keep inventory changes in `inventory/hosts.yml`.
- If playbook behavior changes, update `README.md` to match.
- If Helm addon setup changes, update `helm/README.md` and any referenced values/manifests.
- Keep Kubernetes resources organized by concern:
  - `helm/platform/` for shared cluster services and Helm values
  - `helm/access/` for public access and Cloudflare tunnel resources
  - `helm/apps/` for real application resources
  - `helm/examples/` for throwaway or validation-only examples
- For LAN-only hostnames and local DNS rewrites, prefer `Pi-hole` manifests under `helm/apps/pi-hole/` rather than ad hoc DNS server changes.
- For automatic LAN DNS registration from Kubernetes resources, prefer `helm/platform/external-dns*.yaml` with the Pi-hole provider.
- For self-hosted Git on the LAN, prefer `helm/apps/gitea/` before considering heavier platforms.
- For Gitea CI on this cluster, prefer manifests under `helm/apps/gitea/` and BuildKit-based image builds over ad hoc host-only pipelines.
- For local image distribution, prefer the in-cluster registry manifests under `helm/apps/registry/` and keep k3s containerd registry config in `group_vars/k3s.yml`.
- If the public app hostname or ingress ownership changes, update `helm/apps/spend-app/ingress.yaml`, `helm/README.md`, and `README.md` together.
- Never commit filled secrets; keep credential manifests as templates/examples only.
- Prefer tunnel-based public exposure over router port-forward assumptions when the WAN is behind CGNAT.
- For Cloudflare Tunnel setups that front `ingress-nginx`, preserve `use-forwarded-headers: "true"` in the ingress controller config to avoid HTTPS redirect loops.
- Favor idempotent Ansible tasks over imperative one-off commands.
- When changing install behavior, keep the sequence coherent: prereqs/update, config, install or restart, readiness check, kubeconfig fetch.

## Verification

- Minimum local verification after playbook edits: `ansible-playbook --syntax-check` on changed playbooks.
- If the host is reachable, prefer validating with `playbooks/status.yml` after `install.yml` changes.
