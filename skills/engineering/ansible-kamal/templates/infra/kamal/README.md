# Kamal deployment (__APP_SERVICE__)

Secrets, where they live (`pass` / `custom` vs GitHub), and how to create or rotate them.

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
| **`pass` (local)** | Source of truth; copying values into GitHub; Ansible-only variables | You, on your machine |
| **GitHub Actions secrets** (Environments) | Kamal deploy in CI | GitHub Actions |

## Suggested `pass` paths

Namespace: `__PASS_NAMESPACE__`.

### PostgreSQL (host — aligns with Ansible role)

| Path | Purpose |
|------|---------|
| `__PASS_NAMESPACE__/postgres___APP_SLUG___prod_password` | Password for `__APP_SLUG___prod_user` / DB `__APP_SLUG___production` |
<!-- >>> staging-only -->
| `__PASS_NAMESPACE__/postgres___APP_SLUG___staging_password` | Password for `__APP_SLUG___staging_user` / DB `__APP_SLUG___staging` |
<!-- <<< staging-only -->

### Rails master keys (per environment)

| Path | Purpose |
|------|---------|
| `__PASS_NAMESPACE__/rails_master_key_production` | `RAILS_MASTER_KEY` for production credentials |
<!-- >>> staging-only -->
| `__PASS_NAMESPACE__/rails_master_key_staging` | `RAILS_MASTER_KEY` for staging credentials |
<!-- <<< staging-only -->

### Container registry (GHCR)

| Path | Purpose |
|------|---------|
| `__PASS_NAMESPACE__/kamal_registry_username` | GHCR username or `oauth2`/bot |
| `__PASS_NAMESPACE__/kamal_registry_password` | GHCR PAT with `read:packages` |

### SSH (deploy user — separate from any root key)

| Path | Purpose |
|------|---------|
| `__PASS_NAMESPACE__/deploy_ssh_private_key` | Private key for `__DEPLOY_USER__` (Kamal, CI, local) |
| `__PASS_NAMESPACE__/deploy_ssh_public_key` | Public key — paste into bootstrap as `DEPLOY_SSH_KEY` |
| `__PASS_NAMESPACE__/vps_root_ssh_private_key` | (Optional) Root key used only by you for bootstrap/emergency |

### Optional app secrets

| Path | Purpose |
|------|---------|
| `__PASS_NAMESPACE__/resend_api_key` | Mailer API key (shared across envs) |

## GitHub Actions secrets

Recommended: GitHub Environments `production`<!-- >>> staging-only --> and `staging`<!-- <<< staging-only -->, with the same logical secret names in each.

| Secret | Source `pass` path |
|--------|--------------------|
| `RAILS_MASTER_KEY` | `…/rails_master_key_production` (or `_staging`) |
| `DATABASE_PASSWORD` | `…/postgres___APP_SLUG___prod_password` (or `_staging_`) |
| `RESEND_API_KEY` | `…/resend_api_key` |
| `KAMAL_REGISTRY_USERNAME` / `_PASSWORD` | `…/kamal_registry_username` / `_password` |
| `DEPLOY_SSH_PRIVATE_KEY` | `…/deploy_ssh_private_key` (deploy private key, **not** root) |

Populate from `pass`:

```bash
gh secret set RAILS_MASTER_KEY --env production --body "$(pass show __PASS_NAMESPACE__/rails_master_key_production)"
gh secret set DEPLOY_SSH_PRIVATE_KEY < <(pass show __PASS_NAMESPACE__/deploy_ssh_private_key)
```

## Generating values

```bash
# DB password
openssl rand -base64 32

# Rails master key (creates file + key if missing)
EDITOR="vim" bin/rails credentials:edit --environment production

# Deploy SSH key pair
ssh-keygen -t ed25519 -f ./__DEPLOY_USER__-ed25519 -C "__APP_SERVICE__-kamal-deploy"
pass insert -m __PASS_NAMESPACE__/deploy_ssh_private_key < __DEPLOY_USER__-ed25519
pass insert -m __PASS_NAMESPACE__/deploy_ssh_public_key < __DEPLOY_USER__-ed25519.pub
```

## Operational checklist

1. `pass` paths above filled.
2. Bootstrap once as root: `DEPLOY_SSH_KEY="$(pass show __PASS_NAMESPACE__/deploy_ssh_public_key)" make -C infra/ansible bootstrap`.
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
