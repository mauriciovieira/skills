# Infrastructure (__APP_SERVICE__)

Server provisioning (Ansible) and application deployment (Kamal 2).

## Scope

| Area | Location | Purpose |
|------|----------|---------|
| Ansible playbooks & roles | [`ansible/`](ansible/) | Bootstrap (`deploy` user, sshd, UFW), then `site` (Docker, PostgreSQL on host, optional Traefik) |
| Kamal & secrets | [`kamal/README.md`](kamal/README.md) | Container deploy, secrets, GitHub Actions |
| Kamal config | repo `config/deploy*.yml` | Production (and staging if enabled) destinations |

## High-level topology

One VPS runs:

- **kamal-proxy** (Kamal 2) on **80/443** with Let's Encrypt per app hostname.
- App stack(s) on the **kamal** Docker network.
- **PostgreSQL 16** (PGDG) on the **host OS**, bound to loopback + Docker gateway IPs only, with `pg_hba.conf` limited to localhost + discovered Docker CIDRs and optional UFW allows on 5432 for the same sources.

## Kamal 2 vs Ansible Traefik

Traefik role disabled by default (`traefik_enabled: false` in `ansible/inventory/group_vars/all.yml`). Kamal 2 ships **kamal-proxy** which also binds 80/443. Running both conflicts on ports.

- Default: leave `traefik_enabled: false`.
- To re-enable Traefik, follow Kamal's [continuing to use Traefik](https://kamal-deploy.org/docs/upgrading/continuing-to-use-traefik/) guide.

## Operator quick start

1. Provision the VPS: see [`ansible/README.md`](ansible/README.md).
2. Configure GitHub Environments and secrets: see [`kamal/README.md`](kamal/README.md).
3. Align IP in `ansible/inventory/production.yml` and `config/deploy.yml`.
4. DNS `A`/`AAAA` records → VPS:
   - `__DOMAIN_PROD__`
<!-- >>> staging-only -->
   - `__DOMAIN_STAGING__`
<!-- <<< staging-only -->
