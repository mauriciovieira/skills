#!/usr/bin/env bash
# Local Kamal deploy: load secrets from pass (custom store) and run kamal deploy.
# Usage: ENV=staging|production make deploy   (from repo root)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-__PASS_STORE_DIR_SHELL__}"
export PASSWORD_STORE_DIR

VPS_HOST="${VPS_HOST:-__VPS_IP__}"

pass_show() {
  pass show "$1"
}

docker info >/dev/null 2>&1 || {
  echo "Docker is not running or not reachable. Start Docker Desktop and retry." >&2
  exit 1
}

ENV_RAW="${ENV:-}"
case "$ENV_RAW" in
# >>> staging-only
  staging)
    KAMAL_ARGS=(deploy -d staging)
    SECRET_FILE=".kamal/.deploy-secrets.staging"
    RAILS_KEY_PASS="__PASS_NAMESPACE__/rails_master_key_staging"
    DB_PASS_PASS="__PASS_NAMESPACE__/postgres___APP_SLUG___staging_password"
    ;;
# <<< staging-only
  production)
    KAMAL_ARGS=(deploy)
    SECRET_FILE=".kamal/.deploy-secrets"
    RAILS_KEY_PASS="__PASS_NAMESPACE__/rails_master_key_production"
    DB_PASS_PASS="__PASS_NAMESPACE__/postgres___APP_SLUG___prod_password"
    ;;
  *)
    echo "Invalid or missing ENV. Use: ENV=production make deploy" >&2
    exit 1
    ;;
esac

mkdir -p .kamal
umask 077
pass_show "__PASS_NAMESPACE__/deploy_ssh_private_key" >.kamal/deploy_ssh_key
chmod 600 .kamal/deploy_ssh_key

mkdir -p "$HOME/.ssh"
# Pin the host key on first connect only. ssh-keyscan trusts whatever key the
# network presents (MITM risk), so we add it once and print the fingerprint —
# verify it out-of-band the first time. Skip if already known (no duplicates).
if ! ssh-keygen -F "$VPS_HOST" -f "$HOME/.ssh/known_hosts" >/dev/null 2>&1; then
  echo "Pinning SSH host key for $VPS_HOST — verify this fingerprint out-of-band:" >&2
  ssh-keyscan -H "$VPS_HOST" 2>/dev/null | tee -a "$HOME/.ssh/known_hosts" \
    | ssh-keygen -lf - >&2 2>/dev/null || true
fi

BUILD_COMMIT="$(git rev-parse --short HEAD)"

{
  printf 'KAMAL_REGISTRY_USERNAME=%s\n' "$(pass_show __PASS_NAMESPACE__/kamal_registry_username)"
  printf 'KAMAL_REGISTRY_PASSWORD=%s\n' "$(pass_show __PASS_NAMESPACE__/kamal_registry_password)"
  printf 'RAILS_MASTER_KEY=%s\n' "$(pass_show "$RAILS_KEY_PASS")"
  printf 'DATABASE_PASSWORD=%s\n' "$(pass_show "$DB_PASS_PASS")"
  printf 'RESEND_API_KEY=%s\n' "$(pass_show __PASS_NAMESPACE__/resend_api_key)"
  printf 'BUILD_COMMIT=%s\n' "$BUILD_COMMIT"
} >"$SECRET_FILE"

exec bundle exec kamal "${KAMAL_ARGS[@]}"
