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
