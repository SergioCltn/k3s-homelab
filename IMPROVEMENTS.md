# Improvement Notes

This repo already has a clear Ansible-first shape for managing the k3s host and
the optional Helm/Kubernetes apps. These are the main improvements worth
prioritizing.

## Highest Priority

- Tighten secret hygiene. `.gitignore` currently only ignores `kubeconfig/`,
  while raw secret files can exist locally, such as
  `helm/access/cloudflare-api-token.secret.yaml`,
  `helm/access/cloudflared-token.secret.yaml`,
  `helm/apps/gitea/actions-runner-token.secret.yaml`, and
  `helm/apps/trading-bot/postgres-secret.yaml`. Add ignore rules for raw
  `*.secret.yaml` files while keeping `*.sealedsecret.yaml` and `*.example`
  files trackable.
- Reconcile the docs with the inventory. `README.md` still describes the repo
  as a single-node setup, but `inventory/hosts.yml` includes a `k3s_agents`
  host and `playbooks/install.yml` supports agent installation. Either document
  the worker as optional multi-node support or remove it from the default
  inventory.
- Update the variable list in `README.md`. It mentions `k3s_install_exec`,
  which is not present in `group_vars/k3s.yml`. The current important variables
  include `k3s_agent_config`, `k3s_registries_config`, `k3s_server_group`, and
  `k3s_primary_server`.
- Make k3s installs more reproducible. `playbooks/install.yml` uses the common
  `curl | sh` installer flow with `INSTALL_K3S_CHANNEL=stable`. Consider adding
  a `k3s_version` variable for pinning `INSTALL_K3S_VERSION`, especially before
  using this as unattended cluster reconciliation.

## Kubernetes Operations

- Protect or clearly scope the in-cluster registry. The registry is plain HTTP,
  exposed on the LAN, and trusted by k3s containerd. This is workable on a
  trusted home network, but it should be documented as LAN-trusted only or
  protected with auth/TLS.
- Add resource requests and limits consistently. Some workloads have limits,
  but important services such as the spend-app backend, Postgres, Pi-hole, and
  the registry do not. On a small k3s node this makes noisy workloads harder to
  control.
- Add pod/container security contexts where practical. Most manifests omit
  `securityContext`. Start with non-root-capable apps, then handle apps that
  need elevated privileges or specific UIDs separately.
- Use `StatefulSet` for Postgres. `helm/apps/spend-app/postgres.yaml` currently
  models Postgres as a `Deployment`; a `StatefulSet` better represents stable
  identity and persistent storage ownership.
- Reduce mutable image tags. Current examples include `cloudflare/cloudflared:latest`,
  `pihole/pihole:latest`, `lscr.io/linuxserver/prowlarr:latest`, and local app
  images using `latest`. Pin versions or digests for GitOps-style
  reproducibility.
- Add rollout safety metadata. For long-running deployments, consider
  `revisionHistoryLimit`, explicit update strategy, and availability-oriented
  probes where the upstream image supports them.

## GitOps And Bootstrap

- Document Argo CD recovery. The Argo CD applications point at the in-cluster
  Gitea URL. That is convenient once the cluster is healthy, but bootstrap and
  disaster recovery depend on Gitea being available. A short recovery path would
  make this setup easier to rebuild.
- Decide whether Argo CD should prune. The current applications enable
  self-heal but not prune. That is conservative, but it means deleted manifests
  can leave old resources behind. Keep it if manual resources are common;
  otherwise enable prune per app once the desired ownership model is clear.

## App Exposure

- Harden LAN-only web UIs. Apps such as qBittorrent, Sonarr, Radarr, Prowlarr,
  Jellyfin, Gitea, Grafana, Prometheus, and Argo CD are intentionally LAN-only,
  but they are still reachable by any LAN client that can resolve or hit the
  ingress IP. Add ingress auth where appropriate or document first-login
  hardening steps.
- Keep Cloudflare Tunnel as the preferred public exposure path while the router
  WAN is behind CGNAT. Avoid adding instructions that imply router port
  forwarding is expected to work in this environment.

## Verification

Minimum local verification after playbook changes:

```bash
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ansible-playbook --syntax-check playbooks/install.yml
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ansible-playbook --syntax-check playbooks/status.yml
ANSIBLE_LOCAL_TEMP=/tmp/ansible-local ansible-playbook --syntax-check playbooks/uninstall.yml
```

If the host is reachable, validate remote state with:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/status.yml
```
