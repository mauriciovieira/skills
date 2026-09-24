# Local Ansible run with secrets pulled from a secret command. CI uses -e placeholders.
# Python tooling is isolated in $(VENV); targets refuse to run until the venv exists and contains Ansible.
#
# SECRET_CMD is an absolute path to a command that prints the secret named by
# its argument to stdout. No arguments of its own: this recipe runs with
# infra/ansible as its working directory while the project's other consumers run
# from the project root, so anything relative - including a wrapper whose own
# first word hides a relative path - would name two different files. render.sh
# refuses everything but an absolute path. Wrap anything that needs environment,
# arguments or pipelines in a script and name the script.
# Override: SECRET_CMD=/usr/local/bin/secret make ansible  - or export
# POSTGRES_* yourself and run ansible-playbook directly.

SECRET_CMD ?= __SECRET_CMD__
INVENTORY ?= inventory/production.yml
PLAYBOOK ?= playbooks/site.yml
VENV ?= .venv
USE_UV ?= 0
# After bootstrap.yml, connect as deploy user for site.yml (must match deploy_user in inventory/group_vars/all.yml).
ANSIBLE_REMOTE_USER ?= __DEPLOY_USER__

PY := $(CURDIR)/$(VENV)/bin/python
PIP := $(CURDIR)/$(VENV)/bin/pip
ANSIBLE_PLAYBOOK := $(CURDIR)/$(VENV)/bin/ansible-playbook
ANSIBLE_LINT := $(CURDIR)/$(VENV)/bin/ansible-lint
ANSIBLE_GALAXY := $(CURDIR)/$(VENV)/bin/ansible-galaxy

.PHONY: setup check-venv test ansible bootstrap

setup:
	mise install
ifeq ($(USE_UV),1)
	@command -v uv >/dev/null 2>&1 || { echo >&2 "USE_UV=1 requires uv (https://docs.astral.sh/uv/)."; exit 1; }
	uv venv "$(VENV)"
	uv pip install -r requirements.txt
else
	@test -x "$(PY)" || mise exec -- python -m venv "$(VENV)"
	"$(PIP)" install -U pip
	"$(PIP)" install -r requirements.txt
endif
	"$(ANSIBLE_GALAXY)" collection install -r requirements.yml

check-venv:
	@test -x "$(PY)" || { echo >&2 "No venv at $(VENV). Run: make setup"; exit 1; }
	@test -x "$(ANSIBLE_PLAYBOOK)" || { echo >&2 "ansible-playbook missing in $(VENV). Run: make setup"; exit 1; }
	@test -x "$(ANSIBLE_LINT)" || { echo >&2 "ansible-lint missing in $(VENV). Run: make setup"; exit 1; }
	@"$(PY)" -c 'import ansible, os, sys; root = os.path.dirname(ansible.__file__); pre = sys.prefix; ok = root == pre or root.startswith(pre + os.sep); sys.exit(0 if ok else 1)' || { echo >&2 "Ansible is not installed inside $(VENV) (wrong interpreter?). Run: make setup"; exit 1; }

test: check-venv
	"$(ANSIBLE_PLAYBOOK)" --syntax-check playbooks/bootstrap.yml -i $(INVENTORY) -e deploy_ssh_key=placeholder
	"$(ANSIBLE_PLAYBOOK)" --syntax-check playbooks/site.yml -i $(INVENTORY) \
		-e postgres___APP_SLUG___prod_password=placeholder \
		-e postgres___APP_SLUG___staging_password=placeholder
	"$(ANSIBLE_LINT)" playbooks/ roles/

# Run once per new VPS as root (uses ansible_user from inventory/group_vars).
# Pass the public key via DEPLOY_SSH_KEY (inherited env — do not use -e here; spaces in the key break shell parsing).
bootstrap: check-venv
	@test -n "$$DEPLOY_SSH_KEY" || { echo >&2 "Set DEPLOY_SSH_KEY to the deploy user's public key, e.g. DEPLOY_SSH_KEY=\"\$$(cat ~/.ssh/id_ed25519.pub)\" make bootstrap"; exit 1; }
	"$(ANSIBLE_PLAYBOOK)" -u root -i $(INVENTORY) playbooks/bootstrap.yml

ansible: check-venv
	POSTGRES___APP_SLUG_UPPER___PROD_PASSWORD="$$("$(SECRET_CMD)" __SECRET_NAMESPACE__/postgres___APP_SLUG___prod_password)" \
# >>> staging-only
	POSTGRES___APP_SLUG_UPPER___STAGING_PASSWORD="$$("$(SECRET_CMD)" __SECRET_NAMESPACE__/postgres___APP_SLUG___staging_password)" \
# <<< staging-only
	"$(ANSIBLE_PLAYBOOK)" -u $(ANSIBLE_REMOTE_USER) -i $(INVENTORY) $(PLAYBOOK)
