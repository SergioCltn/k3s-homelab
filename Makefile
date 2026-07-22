SHELL := /bin/bash

INVENTORY := inventory/hosts.yml
KUBECONFIG := ./kubeconfig/aetherion.yaml
TARGET_HOST := aetherion

.PHONY: help
help:
	@printf '%s\n' 'Common targets:'
	@printf '%s\n' '  make install                 Install/reconcile k3s'
	@printf '%s\n' '  make status                  Show k3s status via Ansible'
	@printf '%s\n' '  make nodes                   Show Kubernetes nodes'
	@printf '%s\n' '  make pods                    Show all pods'
	@printf '%s\n' '  make apps                    Show Argo CD apps'
	@printf '%s\n' '  make top                     Show node and pod resource usage'
	@printf '%s\n' '  make tailscale AUTH_KEY=...   Install/configure Tailscale subnet router'
	@printf '%s\n' '  make tailscale-enable        Enable existing Tailscale node'
	@printf '%s\n' '  make tailscale-disable       Disable Tailscale without uninstalling'
	@printf '%s\n' '  make syntax                  Run Ansible syntax checks'
	@printf '%s\n' '  make shutdown CONFIRM=aetherion  Cordon k3s, stop it, then power off'
	@printf '%s\n' '  make uninstall CONFIRM=aetherion Guarded k3s uninstall'

.PHONY: install
install:
	ansible-playbook -i $(INVENTORY) playbooks/install.yml

.PHONY: status
status:
	ansible-playbook -i $(INVENTORY) playbooks/status.yml

.PHONY: nodes
nodes:
	kubectl --kubeconfig $(KUBECONFIG) get nodes -o wide

.PHONY: pods
pods:
	kubectl --kubeconfig $(KUBECONFIG) get pods -A

.PHONY: apps
apps:
	kubectl --kubeconfig $(KUBECONFIG) get applications -n argocd

.PHONY: top
top:
	kubectl --kubeconfig $(KUBECONFIG) top nodes
	kubectl --kubeconfig $(KUBECONFIG) top pods -A --sort-by=cpu

.PHONY: tailscale
tailscale:
	@if [[ -z "$(AUTH_KEY)" ]]; then \
		printf '%s\n' 'Missing AUTH_KEY. Usage: make tailscale AUTH_KEY=tskey-auth-...'; \
		exit 1; \
	fi
	ansible-playbook -i $(INVENTORY) playbooks/tailscale.yml -e tailscale_auth_key=$(AUTH_KEY)

.PHONY: tailscale-enable
tailscale-enable:
	ansible-playbook -i $(INVENTORY) playbooks/tailscale-enable.yml

.PHONY: tailscale-disable
tailscale-disable:
	ansible-playbook -i $(INVENTORY) playbooks/tailscale-disable.yml

.PHONY: syntax
syntax:
	ansible-playbook --syntax-check playbooks/install.yml
	ansible-playbook --syntax-check playbooks/status.yml
	ansible-playbook --syntax-check playbooks/shutdown.yml
	ansible-playbook --syntax-check playbooks/uninstall.yml
	ansible-playbook --syntax-check playbooks/tailscale.yml
	ansible-playbook --syntax-check playbooks/tailscale-enable.yml
	ansible-playbook --syntax-check playbooks/tailscale-disable.yml

.PHONY: shutdown
shutdown:
	@if [[ "$(CONFIRM)" != "$(TARGET_HOST)" ]]; then \
		printf '%s\n' 'Refusing to shut down server.'; \
		printf '%s\n' 'Usage: make shutdown CONFIRM=$(TARGET_HOST)'; \
		exit 1; \
	fi
	ansible-playbook -i $(INVENTORY) playbooks/shutdown.yml -e confirm_shutdown=true -e confirm_target=$(TARGET_HOST)

.PHONY: uninstall
uninstall:
	@if [[ "$(CONFIRM)" != "$(TARGET_HOST)" ]]; then \
		printf '%s\n' 'Refusing to uninstall k3s.'; \
		printf '%s\n' 'Usage: make uninstall CONFIRM=$(TARGET_HOST)'; \
		exit 1; \
	fi
	ansible-playbook -i $(INVENTORY) playbooks/uninstall.yml -e confirm_uninstall=true -e confirm_target=$(TARGET_HOST)
