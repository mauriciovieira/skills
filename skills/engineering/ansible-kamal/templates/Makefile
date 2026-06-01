# __APP_SERVICE__ — root Makefile.
#
# Help convention: each target carries a comment
#   ## Category :: name ## description
# The `help` target (default) parses it with awk and prints the table.

PASSWORD_STORE_DIR ?= __PASS_STORE_DIR_RAW__
VPS_HOST ?= __VPS_IP__

IMAGE ?= __APP_SERVICE__:local
PORT ?= 8080
RAILS_MASTER_KEY_FILE ?= config/credentials/production.key

DATABASE_HOST ?= host.docker.internal
DATABASE_PORT ?= 5432
DATABASE_USERNAME ?= __APP_SLUG___prod_user
DATABASE_PASSWORD ?=
DATABASE_NAME ?= __APP_SLUG___development

KAMAL = bundle exec kamal
DEST  = $(if $(filter staging,$(ENV)),-d staging,)
ROLE ?= web
N    ?= 100

.DEFAULT_GOAL := help

.PHONY: help require-env \
        build run-local mailhog \
        deploy \
        logs kamal-console kamal-dbconsole kamal-migrate kamal-shell kamal-exec \
        ansible-setup ansible-test ansible-bootstrap ansible-run \
        db-restore-from-vps

## Meta :: help ## List available targets (this text)
help:
	@awk 'BEGIN { \
	    FS=" ## "; \
	    printf "Usage: make <target> [ENV=staging|production]\n\n"; \
	    printf "Examples:\n"; \
	    printf "  make deploy ENV=production\n"; \
	    printf "  make logs ENV=production ROLE=worker N=500\n"; \
	    printf "  ENV=production make kamal-dbconsole\n\n"; \
	  } \
	  /^## .+ :: [^ ]+ ## .+/ { \
	    sub(/^## /, ""); \
	    split($$1, head, " :: "); \
	    cat = head[1]; target = head[2]; desc = $$2; \
	    if (!(cat in seen)) { order[++n] = cat; seen[cat] = 1 } \
	    lines[cat] = lines[cat] sprintf("  %-20s %s\n", target, desc); \
	  } \
	  END { \
	    for (i = 1; i <= n; i++) { c = order[i]; printf "%s\n%s\n", c, lines[c] } \
	  }' $(MAKEFILE_LIST)

require-env:
	@test -n "$(ENV)" || { echo >&2 "ENV required: staging|production"; exit 1; }
	@case "$(ENV)" in staging|production) ;; *) \
	  echo >&2 "ENV invalid: '$(ENV)' (use staging|production)"; exit 1;; esac

## Local :: build ## Build local Docker image (__APP_SERVICE__:local)
build:
	docker build -t $(IMAGE) .

## Local :: mailhog ## Start MailHog (SMTP :1025, UI http://localhost:8025)
mailhog:
	docker run --rm -p 1025:1025 -p 8025:8025 mailhog/mailhog:latest

## Local :: run-local ## Run prod image locally at http://localhost:$(PORT)
run-local:
	@key=""; \
	if [ -n "$$RAILS_MASTER_KEY" ]; then \
	  key="$$RAILS_MASTER_KEY"; \
	elif [ -f "$(RAILS_MASTER_KEY_FILE)" ]; then \
	  key="$$(cat $(RAILS_MASTER_KEY_FILE))"; \
	elif [ -f config/master.key ]; then \
	  key="$$(cat config/master.key)"; \
	else \
	  echo >&2 "No Rails credentials key found. The local image uses RAILS_ENV=production. Options:"; \
	  echo >&2 "  export RAILS_MASTER_KEY=... && make run-local"; \
	  echo >&2 "  add $(RAILS_MASTER_KEY_FILE) (default for production.yml.enc)"; \
	  echo >&2 "  add config/master.key (for credentials.yml.enc only)"; \
	  exit 1; \
	fi; \
	resend_api_key="$$RESEND_API_KEY"; \
	if [ -z "$$resend_api_key" ] && [ -f .env ]; then \
	  resend_api_key="$$(sed -n 's/^RESEND_API_KEY=//p' .env | head -n 1)"; \
	fi; \
	use_mailhog="$$USE_MAILHOG"; \
	if [ -z "$$use_mailhog" ] && [ -f .env ]; then \
	  use_mailhog="$$(sed -n 's/^USE_MAILHOG=//p' .env | head -n 1)"; \
	fi; \
	mailhog_host="$$MAILHOG_SMTP_HOST"; \
	if [ -z "$$mailhog_host" ] && [ -f .env ]; then \
	  mailhog_host="$$(sed -n 's/^MAILHOG_SMTP_HOST=//p' .env | head -n 1)"; \
	fi; \
	mailhog_port="$$MAILHOG_SMTP_PORT"; \
	if [ -z "$$mailhog_port" ] && [ -f .env ]; then \
	  mailhog_port="$$(sed -n 's/^MAILHOG_SMTP_PORT=//p' .env | head -n 1)"; \
	fi; \
	docker run --rm -p $(PORT):80 \
		-e RAILS_MASTER_KEY="$$key" \
		-e HOST_IP="localhost:$(PORT)" \
		-e LOCAL_DOCKER_RUN="1" \
		-e USE_MAILHOG="$$use_mailhog" \
		-e MAILHOG_SMTP_HOST="$$mailhog_host" \
		-e MAILHOG_SMTP_PORT="$$mailhog_port" \
		-e DATABASE_HOST="$(DATABASE_HOST)" \
		-e DATABASE_PORT="$(DATABASE_PORT)" \
		-e DATABASE_USERNAME="$(DATABASE_USERNAME)" \
		-e DATABASE_PASSWORD="$(DATABASE_PASSWORD)" \
		-e DATABASE_NAME="$(DATABASE_NAME)" \
		-e RESEND_API_KEY="$$resend_api_key" \
		$(IMAGE)

## Deploy :: deploy ## Deploy via Kamal (ENV=staging|production)
deploy: require-env
	@ENV=$(ENV) PASSWORD_STORE_DIR="$(PASSWORD_STORE_DIR)" VPS_HOST="$(VPS_HOST)" ./scripts/kamal-deploy-from-pass.sh

## Kamal (ENV required) :: logs ## Container logs (ROLE=web|worker N=200 FOLLOW=1)
logs: require-env
	$(KAMAL) app logs $(DEST) -r $(ROLE) -n $(N) $(if $(FOLLOW),-f)

## Kamal (ENV required) :: kamal-console ## Open Rails console in the web container
kamal-console: require-env
	$(KAMAL) app exec $(DEST) -i --reuse "bin/rails console"

## Kamal (ENV required) :: kamal-dbconsole ## Open dbconsole (psql) in the web container
kamal-dbconsole: require-env
	$(KAMAL) app exec $(DEST) -i --reuse "bin/rails dbconsole"

## Kamal (ENV required) :: kamal-migrate ## Run bin/rails db:migrate in the web container
kamal-migrate: require-env
	$(KAMAL) app exec $(DEST) --reuse "bin/rails db:migrate"

## Kamal (ENV required) :: kamal-shell ## Open bash in the web container
kamal-shell: require-env
	$(KAMAL) app exec $(DEST) -i --reuse bash

## Kamal (ENV required) :: kamal-exec ## Run CMD='...' in the web container (use single quotes)
kamal-exec: require-env
	@test -n "$(CMD)" || { echo >&2 "CMD required, e.g.: CMD='bin/rails runner \"puts 1\"'"; exit 1; }
	$(KAMAL) app exec $(DEST) -i --reuse '$(CMD)'

## Ansible :: ansible-setup ## Create venv and install collections (infra/ansible)
ansible-setup:
	$(MAKE) -C infra/ansible setup

## Ansible :: ansible-test ## Lint + syntax-check the playbooks
ansible-test:
	$(MAKE) -C infra/ansible test

## Ansible :: ansible-bootstrap ## Initial VPS hardening (run once; DEPLOY_SSH_KEY=...)
ansible-bootstrap:
	@test -n "$$DEPLOY_SSH_KEY" || { echo >&2 \
	  "DEPLOY_SSH_KEY required, e.g.: DEPLOY_SSH_KEY=\"\$$(cat ~/.ssh/id_ed25519.pub)\" make ansible-bootstrap"; \
	  exit 1; }
	$(MAKE) -C infra/ansible bootstrap

## Ansible :: ansible-run ## Provision the VPS (site.yml) as the deploy user
ansible-run:
	$(MAKE) -C infra/ansible ansible

## DB :: db-restore-from-vps ## Restore a VPS dump into the local database (ENV=staging|production)
db-restore-from-vps: require-env
	@ENV=$(ENV) PASSWORD_STORE_DIR="$(PASSWORD_STORE_DIR)" ./scripts/db-restore-from-vps.sh
