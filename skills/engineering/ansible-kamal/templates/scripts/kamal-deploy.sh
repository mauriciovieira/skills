#!/usr/bin/env bash
# Local Kamal deploy: load secrets from the configured secret command and run kamal deploy.
# Usage: ENV=staging|production make deploy   (from repo root)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Absolute path to a command that prints the secret named by its argument to
# stdout. Override per invocation:
#   SECRET_CMD=/usr/local/bin/secret ENV=production make deploy
SECRET_CMD="${SECRET_CMD:-__SECRET_CMD__}"

VPS_HOST="${VPS_HOST:-__VPS_IP__}"

# SECRET_CMD is an absolute path with no arguments, so the expansion is quoted:
# no word splitting, no globbing, nothing to disable.
secret() {
  "$SECRET_CMD" "$1"
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
    RAILS_KEY_NAME="__SECRET_NAMESPACE__/rails_master_key_staging"
    DB_PASSWORD_NAME="__SECRET_NAMESPACE__/postgres___APP_SLUG___staging_password"
    ;;
# <<< staging-only
  production)
    KAMAL_ARGS=(deploy)
    SECRET_FILE=".kamal/.deploy-secrets"
    RAILS_KEY_NAME="__SECRET_NAMESPACE__/rails_master_key_production"
    DB_PASSWORD_NAME="__SECRET_NAMESPACE__/postgres___APP_SLUG___prod_password"
    ;;
  *)
    echo "Invalid or missing ENV. Use: ENV=production make deploy" >&2
    exit 1
    ;;
esac

mkdir -p .kamal
umask 077
secret "__SECRET_NAMESPACE__/deploy_ssh_private_key" >.kamal/deploy_ssh_key
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
  printf 'KAMAL_REGISTRY_USERNAME=%s\n' "$(secret __SECRET_NAMESPACE__/kamal_registry_username)"
  printf 'KAMAL_REGISTRY_PASSWORD=%s\n' "$(secret __SECRET_NAMESPACE__/kamal_registry_password)"
  printf 'RAILS_MASTER_KEY=%s\n' "$(secret "$RAILS_KEY_NAME")"
  printf 'DATABASE_PASSWORD=%s\n' "$(secret "$DB_PASSWORD_NAME")"
  printf 'RESEND_API_KEY=%s\n' "$(secret __SECRET_NAMESPACE__/resend_api_key)"
  printf 'BUILD_COMMIT=%s\n' "$BUILD_COMMIT"
} >"$SECRET_FILE"

exec bundle exec kamal "${KAMAL_ARGS[@]}"
