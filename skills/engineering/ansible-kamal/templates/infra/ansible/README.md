# Ansible — __APP_SERVICE__ VPS

Provisions a single Ubuntu VPS with hardened baseline, Docker, optional Traefik (off by default — Kamal 2 owns 80/443), and PostgreSQL 16 on the host for the app database(s).

Parent overview: [`../README.md`](../README.md).

## Layout

```text
infra/ansible/
├── ansible.cfg          # roles_path = ./roles
├── inventory/
│   ├── production.yml
│   └── group_vars/all.yml      # timezone, deploy user, PG passwords from env, traefik_enabled
├── playbooks/
│   ├── bootstrap.yml    # one-time: common, users, ssh_bootstrap, firewall (UFW), opt
│   ├── site.yml         # full provision (common → users → fail2ban → docker → postgresql → traefik)
│   ├── dump_db.yml      # pg_dump on remote, fetch local
│   └── restore_db.yml   # restore local dump onto remote DB
├── roles/               # common, users, ssh_bootstrap, firewall, fail2ban, docker, postgresql, traefik, opt
├── Makefile             # make setup | test | bootstrap | ansible
├── requirements.txt
└── requirements.yml
```

## Prerequisites (operator laptop)

- Python 3.12+ (managed via `mise`).
- **Two SSH keys**:
  1. A key already in `root@<server>`'s `authorized_keys` — runs `bootstrap.yml` as root.
  2. A dedicated deploy key pair (private for Kamal/CI; public goes to bootstrap as `deploy_ssh_key`).
- `pass` / `custom` with secrets under your chosen namespace (`__PASS_NAMESPACE__/...`). See [`../kamal/README.md`](../kamal/README.md).

## Local setup

```bash
cd infra/ansible
make setup          # venv + pip + ansible-galaxy collections
make test           # syntax-check + ansible-lint (no SSH)
```

## Bootstrap (one-time per host; idempotent)

Runs as root. Order: `common` → `users` (creates `__DEPLOY_USER__`, restricted sudo, deploy key) → `ssh_bootstrap` (sshd drop-ins) → `firewall` (UFW reset → defaults → allow 22/80/443 → enable → re-hook) → `opt`.

```bash
cd infra/ansible
DEPLOY_SSH_KEY="$(cat ~/.ssh/__DEPLOY_USER__.pub)" make bootstrap
```

`DEPLOY_SSH_KEY` here is the **public** key of the deploy user, not the root key.

## Full provision (`site.yml`)

Run after bootstrap so `make ansible` can SSH as the deploy user. Loads PG passwords via `pass`:

```bash
cd infra/ansible
make ansible
```

## PostgreSQL

- **Version 16** via PGDG.
- **Listen** on `127.0.0.1` plus IPv4 gateway IPs of Docker networks listed in `postgresql_docker_network_names` (default: `bridge`, `proxy`/`docker_network_name`, `kamal`). Falls back to `docker0` and `postgresql_fallback_docker_cidr` (`172.17.0.0/16`) when networks don't exist yet.
- **`pg_hba.conf`** allows only the app users from `127.0.0.1/32` + discovered (or fallback) Docker CIDRs.
- **UFW** layer (extra) on port 5432 for the same sources (toggle `postgresql_firewall_ufw_enable`).

Application containers reach the host via `host.docker.internal` (see Kamal `add-host` in `config/deploy.yml`).

## Troubleshooting

- **UFW "allows" 22 but SSH times out**: `nft list chain ip filter INPUT` — if no `jump ufw-…`, Docker orphaned the IPv4 chains. The `firewall` and `docker` roles include `nft_input_rehook.yml` which auto-recovers (`ufw disable && ufw --force enable`).
- **HTTPS / Let's Encrypt fails from kamal-proxy** while host can reach Let's Encrypt: Docker bridge MTU. The `docker` role writes `/etc/docker/daemon.json` with `mtu: 1450` (`docker_daemon_mtu`).
- **`make ansible` times out mid-play**: re-run `make bootstrap` to re-enable UFW with `DEFAULT_FORWARD_POLICY=ACCEPT`.
- **Permission denied for deploy user**: `make bootstrap` first so the user + key exist.
