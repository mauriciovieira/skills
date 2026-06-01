---
name: ansible-kamal
description: Use when bootstrapping a Rails project that needs Ubuntu VPS provisioning (Ansible) and Kamal 2 deploy (kamal-proxy on 80/443) — scaffolds infra/ansible, infra/kamal, config/deploy*.yml, .kamal/secrets* templates from a hardened reference layout, asking IP, DNS, and whether the host runs both staging+production or only a single domain.
---

# ansible-kamal

Scaffolds a full **Ansible + Kamal 2** infrastructure tree for a Rails app on a single Ubuntu VPS. Generates:

- **Root `Makefile`** — `make deploy ENV=…`, `make db-restore-from-vps ENV=…`, `make build`, `make run-local`, `make mailhog`.
- **Root `scripts/`** — `kamal-deploy-from-pass.sh`, `db-restore-from-vps.sh` (provider-agnostic — works with Hetzner, DigitalOcean, OVH, Hostinger, AWS Lightsail, etc., as long as the Ansible inventory points at the box).
- `infra/ansible/` — playbooks (`bootstrap`, `site`, `dump_db`, `restore_db`), roles (`common`, `users`, `ssh_bootstrap`, `firewall`, `fail2ban`, `docker`, `postgresql`, `traefik`, `opt`), inventory, **`Makefile`** (`setup`, `test`, `bootstrap`, `ansible`), README.
- `infra/kamal/README.md` — secrets / `pass` / GitHub Actions guide.
- `config/deploy.yml` (+ `config/deploy.staging.yml` if staging is enabled).
- `.kamal/secrets`, `.kamal/secrets-common` (+ `.kamal/secrets.staging` if enabled).

## When to Use

- A new Rails project that needs a single Ubuntu VPS with Kamal 2 + host PostgreSQL 16.
- An existing project missing `infra/ansible/` where you want the same hardened baseline (UFW, fail2ban, sshd drop-in, Docker, PG on host).

**Do NOT use** when the project already has `infra/ansible/` — diff manually instead, this skill overwrites.

## Inputs to ask the user (in this order)

1. **App slug (snake_case)** — e.g. `myapp`, `petshop`. Used for DB names (`<slug>_production`, `<slug>_staging`), DB users (`<slug>_prod_user`, `<slug>_staging_user`), and env var prefix (`POSTGRES_<SLUG_UPPER>_PROD_PASSWORD`).
2. **Service name (kebab-case)** — Kamal `service:` and image name. Default = slug with `_`→`-` (e.g. `my-app`).
3. **Image repo** — e.g. `myorg/<service>` for GHCR.
4. **VPS IP (IPv4)** — host key in `inventory/production.yml` and `config/deploy.yml` `servers.web.hosts`.
5. **Inventory group name** — Ansible group; default = slug (e.g. `myapp`).
6. **Environment mode** — ONE of:
   - `staging+production` — two Kamal destinations, two DBs, two domains (recommended for production apps).
   - `single` — only one domain / DB / Kamal destination, no staging plumbing emitted.
7. **Production domain** — e.g. `example.com`.
8. **Staging domain** — only if `staging+production`. Default = `staging.<production_domain>`.
9. **Let's Encrypt email** — for kamal-proxy ACME (and Traefik if ever enabled).
10. **Deploy user** — Linux user Ansible (`site.yml`) + Kamal SSH as. Default = `<slug>_deploy`. Must NOT be `root`.
11. **Pass backend** — `custom` (uses a custom `PASSWORD_STORE_DIR`, e.g. `~/.password-store-custom`) or `pass` (default `~/.password-store`).
12. **Pass namespace** — e.g. `infra/myapp`. Default = `infra/<inventory_group>`.

## Variable map

After collecting inputs, derive:

| Placeholder | Value |
|-------------|-------|
| `__APP_SLUG__` | snake_case slug |
| `__APP_SERVICE__` | kebab-case service |
| `__APP_SLUG_UPPER__` | uppercase snake_case (env var prefix) |
| `__INVENTORY_GROUP__` | inventory group |
| `__VPS_IP__` | IPv4 |
| `__DOMAIN_PROD__` | production FQDN |
| `__DOMAIN_STAGING__` | staging FQDN (or empty in `single` mode) |
| `__LETSENCRYPT_EMAIL__` | ACME email |
| `__DEPLOY_USER__` | deploy linux user |
| `__IMAGE_REPO__` | container image (no tag) |
| `__PASS_BACKEND__` | `custom` or `pass` |
| `__PASS_STORE_DIR__` | `$(HOME)/.password-store-custom` or empty for default |
| `__PASS_NAMESPACE__` | e.g. `infra/myapp` |
| `__ENV_MODE__` | `staging+production` or `single` |

## How to scaffold

Run the render script from the **target project root** (the repo to scaffold INTO):

```bash
APP_SLUG=myapp \
APP_SERVICE=my-app \
APP_SLUG_UPPER=MYAPP \
INVENTORY_GROUP=myapp \
VPS_IP=203.0.113.10 \
DOMAIN_PROD=example.com \
DOMAIN_STAGING=staging.example.com \
LETSENCRYPT_EMAIL=admin@example.com \
DEPLOY_USER=myapp_deploy \
IMAGE_REPO=myorg/my-app \
PASS_BACKEND=custom \
PASS_STORE_DIR='$(HOME)/.password-store-custom' \
PASS_NAMESPACE=infra/myapp \
ENV_MODE=staging+production \
TARGET_DIR=. \
~/.claude/skills/ansible-kamal/scripts/render.sh
```

For `ENV_MODE=single` leave `DOMAIN_STAGING` empty (or unset). `PASS_STORE_DIR` may be empty when `PASS_BACKEND=pass`.

The script:

1. Walks `templates/`, applies placeholder substitution.
2. Strips blocks fenced by `# >>> staging-only` / `# <<< staging-only` when `ENV_MODE=single`.
3. Skips files matching `*.staging.*` and `secrets.staging` when `ENV_MODE=single`.
4. Renames `*.tmpl` → no suffix.
5. Refuses to overwrite existing `infra/ansible/` unless `FORCE=1`.

## After scaffold

Tell the user, in order:

1. `cd infra/ansible && make setup && make test` — bootstraps venv + galaxy collections + lints.
2. Generate deploy SSH key pair, `pass insert -m __PASS_NAMESPACE__/deploy_ssh_{private,public}_key`.
3. Generate DB passwords: `openssl rand -base64 32`, store at `__PASS_NAMESPACE__/postgres___APP_SLUG___prod_password` (and `_staging_` if applicable).
4. DNS `A` records: `__DOMAIN_PROD__` (+ `__DOMAIN_STAGING__`) → `__VPS_IP__`.
5. Open the VPS provider's firewall (or `ufw`): allow 22/80/443 from anywhere (or your IP for 22).
6. Run `DEPLOY_SSH_KEY="$(pass show __PASS_NAMESPACE__/deploy_ssh_public_key)" make bootstrap` (root reachable).
7. Run `make ansible` (loads PG passwords from pass and provisions `site.yml` as `__DEPLOY_USER__`).
8. Wire GitHub Environments + secrets per `infra/kamal/README.md`.
9. `bundle exec kamal setup` (production) and `bundle exec kamal setup -d staging` (if staging).

## Known constraints baked in

- **PostgreSQL on host**, not Docker accessory. Containers reach it via `host.docker.internal` (`add-host: host.docker.internal:host-gateway` in deploy.yml).
- **kamal-proxy** owns 80/443 (Traefik role disabled by default; kept in tree).
- **UFW** runs in `bootstrap.yml` only, with `MANAGE_BUILTINS=yes` and `DEFAULT_FORWARD_POLICY=ACCEPT` so SSH survives Docker's iptables hooks. Includes nft INPUT rehook task to recover from Docker orphaning UFW jumps.
- **sshd drop-in** `05-ansible-sshd-hardening.conf` in bootstrap; cloud-init `50-` and `60-` removed.
- **Deploy user sudo** restricted to `systemctl`, `apt`, `apt-get`. No `/etc/ssh` editing.
- **Docker daemon MTU 1450** for Let's Encrypt egress on cloud bridges.

## Files emitted (full list)

```
Makefile                          # root: deploy, db-restore-from-vps, build, run-local, mailhog
scripts/kamal-deploy-from-pass.sh
scripts/db-restore-from-vps.sh
infra/README.md
infra/ansible/ansible.cfg
infra/ansible/Makefile            # ansible: setup, test, bootstrap, ansible
infra/ansible/README.md
infra/ansible/requirements.txt
infra/ansible/requirements.yml
infra/ansible/playbooks/{bootstrap,site,dump_db,restore_db}.yml
infra/ansible/inventory/production.yml
infra/ansible/inventory/group_vars/all.yml
infra/ansible/roles/common/tasks/main.yml
infra/ansible/roles/users/tasks/main.yml
infra/ansible/roles/users/library/managed_authorized_key.py     # idempotent single-key authorized_keys module
infra/ansible/roles/ssh_bootstrap/{tasks/main.yml,templates/sshd_ansible_hardening.conf.j2,handlers/main.yml}
infra/ansible/roles/firewall/tasks/{main,nft_input_rehook}.yml
infra/ansible/roles/fail2ban/{tasks/main.yml,handlers/main.yml}
infra/ansible/roles/docker/{tasks/main.yml,templates/daemon.json.j2,handlers/main.yml}
infra/ansible/roles/postgresql/{tasks/{main,discover,ufw}.yml,templates/{postgresql.conf,pg_hba.conf,create_databases.sql}.j2,handlers/main.yml}
infra/ansible/roles/opt/tasks/main.yml
infra/ansible/roles/traefik/{tasks/main.yml,templates/{traefik.yml,docker-compose.yml}.j2}
infra/kamal/README.md
config/deploy.yml
config/deploy.staging.yml         # only if ENV_MODE=staging+production
.kamal/secrets
.kamal/secrets-common
.kamal/secrets.staging            # only if ENV_MODE=staging+production
```

## Common mistakes

| Mistake | Fix |
|--------|-----|
| Forgot `__VPS_IP__` substitution → bootstrap connects to placeholder | Re-run `render.sh`; verify `inventory/production.yml` and `config/deploy.yml` have the IP. |
| Used `__APP_SLUG__` with hyphens | Slug must be snake_case; service name is the kebab-case form. Postgres identifiers reject hyphens. |
| `single` mode but staging files present | Set `ENV_MODE=single`, leave `DOMAIN_STAGING` empty, re-render. |
| Deploy user = `root` | Disallowed; `users` role creates it as a non-sudo account with restricted sudoers. Pick `<slug>_deploy`. |
| Pass paths don't match Makefile | `__PASS_NAMESPACE__` flows into Makefile `make ansible` target. Match what's in `pass`. |
