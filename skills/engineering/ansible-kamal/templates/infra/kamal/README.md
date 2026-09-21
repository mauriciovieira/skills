# Kamal deployment (__APP_SERVICE__)

Secrets, where they live (your local secret manager vs GitHub), and how to create or rotate them.

Related: [`../README.md`](../README.md), [`../ansible/README.md`](../ansible/README.md).

## Runtime mapping

| Hostname | `RAILS_ENV` | Kamal config |
|----------|-------------|--------------|
| `__DOMAIN_PROD__` | `production` | `config/deploy.yml` |
<!-- >>> staging-only -->
| `__DOMAIN_STAGING__` | `staging` | `config/deploy.staging.yml` |
<!-- <<< staging-only -->

DB connectivity is to **PostgreSQL on the host**. Kamal sets `DATABASE_HOST=host.docker.internal` and `servers.web.options.add-host: host.docker.internal:host-gateway`.

## Two stores for secrets

| Store | Used for | Who reads it |
|-------|----------|--------------|
| **Local secret manager** | Source of truth; copying values into GitHub; Ansible-only variables | You, on your machine |
| **GitHub Actions secrets** (Environments) | Kamal deploy in CI | GitHub Actions |

Nothing here assumes a particular manager. `make deploy`, `make db-restore-from-vps`
and `make -C infra/ansible ansible` all read secrets by calling `$(SECRET_CMD)` with
one secret name as its last argument and reading the value from stdout. Point
`SECRET_CMD` at whatever you already use, wrapping it in a script if the lookup
needs more than a plain command.

That wrapper must be on your `PATH` or named by an absolute path, never a
relative one: the two scripts run from the project root while `make -C
infra/ansible ansible` runs from `infra/ansible`, so `./bin/secret` would mean
two different files. `render.sh` rejects a relative path for that reason.

```sh
#!/usr/bin/env bash
# secret - called as: secret __SECRET_NAMESPACE__/rails_master_key_production
set -euo pipefail
your-secret-manager read "$1"
```

Put it somewhere on `PATH` and make it executable, then render with
`SECRET_CMD=secret`.

`SECRET_CMD` may carry fixed arguments before the secret name, so it is split on
whitespace. A command whose own path contains a space therefore cannot work; its
arguments are free to contain anything but `$` and `~`, which make and `/bin/sh`
would expand while the generated scripts would not.

## Secret names

Namespace: `__SECRET_NAMESPACE__`.

### PostgreSQL (host — aligns with Ansible role)

| Path | Purpose |
|------|---------|
| `__SECRET_NAMESPACE__/postgres___APP_SLUG___prod_password` | Password for `__APP_SLUG___prod_user` / DB `__APP_SLUG___production` |
<!-- >>> staging-only -->
| `__SECRET_NAMESPACE__/postgres___APP_SLUG___staging_password` | Password for `__APP_SLUG___staging_user` / DB `__APP_SLUG___staging` |
<!-- <<< staging-only -->

### Rails master keys (per environment)

| Path | Purpose |
|------|---------|
| `__SECRET_NAMESPACE__/rails_master_key_production` | `RAILS_MASTER_KEY` for production credentials |
<!-- >>> staging-only -->
| `__SECRET_NAMESPACE__/rails_master_key_staging` | `RAILS_MASTER_KEY` for staging credentials |
<!-- <<< staging-only -->

### Container registry (GHCR)

| Path | Purpose |
|------|---------|
| `__SECRET_NAMESPACE__/kamal_registry_username` | GHCR username or `oauth2`/bot |
| `__SECRET_NAMESPACE__/kamal_registry_password` | GHCR PAT with `read:packages` |

### SSH (deploy user — separate from any root key)

| Path | Purpose |
|------|---------|
| `__SECRET_NAMESPACE__/deploy_ssh_private_key` | Private key for `__DEPLOY_USER__` (Kamal, CI, local) |
| `__SECRET_NAMESPACE__/deploy_ssh_public_key` | Public key - paste into bootstrap as `DEPLOY_SSH_KEY` |
| `__SECRET_NAMESPACE__/vps_root_ssh_private_key` | (Optional) Root key used only by you for bootstrap/emergency |

### Optional app secrets

| Path | Purpose |
|------|---------|
| `__SECRET_NAMESPACE__/resend_api_key` | Mailer API key (shared across envs) |

## GitHub Actions secrets

Recommended: GitHub Environments `production`<!-- >>> staging-only --> and `staging`<!-- <<< staging-only -->, with the same logical secret names in each.

| Secret | Source secret name |
|--------|--------------------|
| `RAILS_MASTER_KEY` | `…/rails_master_key_production` (or `_staging`) |
| `DATABASE_PASSWORD` | `…/postgres___APP_SLUG___prod_password` (or `_staging_`) |
| `RESEND_API_KEY` | `…/resend_api_key` |
| `KAMAL_REGISTRY_USERNAME` / `_PASSWORD` | `…/kamal_registry_username` / `_password` |
| `DEPLOY_SSH_PRIVATE_KEY` | `…/deploy_ssh_private_key` (deploy private key, **not** root) |

Populate them. `gh secret set` with no `--body` prompts for the value, so nothing
lands in your shell history; a key that lives in a file is redirected in:

```bash
gh secret set RAILS_MASTER_KEY --env production
gh secret set DEPLOY_SSH_PRIVATE_KEY --env production < ./__DEPLOY_USER__-ed25519
```

## Generating values

```bash
# DB password
openssl rand -base64 32

# Rails master key (creates file + key if missing)
EDITOR="vim" bin/rails credentials:edit --environment production

# Deploy SSH key pair
ssh-keygen -t ed25519 -f ./__DEPLOY_USER__-ed25519 -C "__APP_SERVICE__-kamal-deploy"
# Store both halves under the names above, then delete the local files.
```

## Operational checklist

1. Secret names above filled in your manager, and `SECRET_CMD` resolving them.
2. Bootstrap once as root: `DEPLOY_SSH_KEY="$($SECRET_CMD __SECRET_NAMESPACE__/deploy_ssh_public_key)" make -C infra/ansible bootstrap`.
3. Site provision: `make -C infra/ansible ansible`.
4. GitHub: environments + secrets.
5. Local deploy:

```bash
ENV=production make deploy
<!-- >>> staging-only -->
ENV=staging make deploy
<!-- <<< staging-only -->
```

6. Local DB restore from VPS:

```bash
ENV=production make db-restore-from-vps
<!-- >>> staging-only -->
ENV=staging make db-restore-from-vps
<!-- <<< staging-only -->
```

## TLS / Let's Encrypt (kamal-proxy)

Symptoms of MTU issue: kamal-proxy logs show `acme/autocert: missing certificate` or `i/o timeout` to `acme-v02.api.letsencrypt.org` while host can reach it. Fix: re-run `make -C infra/ansible ansible` (Docker daemon `mtu: 1450`), `sudo systemctl restart docker`, `kamal proxy reboot`.
