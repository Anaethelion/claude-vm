.PHONY: setup start check test venv help

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*##"}; {printf "  %-10s %s\n", $$1, $$2}'

.DEFAULT_GOAL := help

venv: .venv/bin/ansible-playbook ## Set up Ansible venv

.venv/bin/ansible-playbook: requirements.txt
	python3 -m venv .venv
	.venv/bin/pip install -r requirements.txt
	.venv/bin/ansible-galaxy collection install community.general
	@touch .venv/bin/ansible-playbook

setup: venv ## Create and provision the VM (one-time)
	./setup-vm.sh

start: ## Launch the VM with mounts
	./start-vm.sh

check: venv ## Diff what Ansible would change (no writes)
	./setup-vm.sh --check

test: ## Run the test suite
	bats tests/
