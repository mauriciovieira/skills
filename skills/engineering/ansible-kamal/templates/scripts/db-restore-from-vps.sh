#!/usr/bin/env bash
# Download server Postgres dump (staging/production) from the VPS and restore locally.
# Provider-agnostic: works against any Ubuntu VPS provisioned by infra/ansible
# (Hostinger, Hetzner, DigitalOcean, OVH, AWS Lightsail, …) — just point inventory at the host.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-__PASS_STORE_DIR_SHELL__}"
export PASSWORD_STORE_DIR

pass_show() {
  pass show "$1"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd pass
require_cmd mktemp
require_cmd pg_restore
require_cmd psql
require_cmd dropdb
require_cmd createdb

if [[ -x "infra/ansible/.venv/bin/ansible-playbook" ]]; then
  ANSIBLE_PLAYBOOK="infra/ansible/.venv/bin/ansible-playbook"
else
  require_cmd ansible-playbook
  ANSIBLE_PLAYBOOK="ansible-playbook"
fi

ENV_RAW="${ENV:-}"
case "$ENV_RAW" in
# >>> staging-only
  staging)
    SOURCE_DB_NAME="__APP_SLUG___staging"
    SOURCE_DB_USER="__APP_SLUG___staging_user"
    SOURCE_DB_PASSWORD_PASS="__PASS_NAMESPACE__/postgres___APP_SLUG___staging_password"
    CONFIRMATION="RESTORE staging INTO local"
    ;;
# <<< staging-only
  production)
    SOURCE_DB_NAME="__APP_SLUG___production"
    SOURCE_DB_USER="__APP_SLUG___prod_user"
    SOURCE_DB_PASSWORD_PASS="__PASS_NAMESPACE__/postgres___APP_SLUG___prod_password"
    CONFIRMATION="RESTORE production INTO local"
    ;;
  *)
    echo "Invalid or missing ENV. Use: ENV=production make db-restore-from-vps" >&2
    exit 1
    ;;
esac

read -r -p "Type '$CONFIRMATION' to continue: " typed_confirmation
if [[ "$typed_confirmation" != "$CONFIRMATION" ]]; then
  echo "Confirmation did not match. Aborting." >&2
  exit 1
fi

DUMP_DB_PASSWORD="$(pass_show "$SOURCE_DB_PASSWORD_PASS")"

mkdir -p .tmp
umask 077
CACHED_DUMP_FILE="$ROOT/.tmp/${ENV_RAW}-vps-db-latest.dump"
DUMP_FILE="$CACHED_DUMP_FILE"

download_dump="yes"
if [[ -s "$CACHED_DUMP_FILE" ]]; then
  read -r -p "Local dump already exists at '$CACHED_DUMP_FILE'. Generate a fresh dump from server and download again? [y/N]: " regenerate_dump
  case "${regenerate_dump:-}" in
    y|Y|yes|YES)
      download_dump="yes"
      ;;
    *)
      download_dump="no"
      ;;
  esac
fi

if [[ "$download_dump" == "yes" ]]; then
  TEMP_DUMP_FILE="$(mktemp "$ROOT/.tmp/${ENV_RAW}-vps-db-XXXXXX.dump")"
  trap 'rm -f "$TEMP_DUMP_FILE"' EXIT

  echo "Dumping remote PostgreSQL ($ENV_RAW) to local file..."
  DUMP_DB_PASSWORD="$DUMP_DB_PASSWORD" \
  "$ANSIBLE_PLAYBOOK" \
    -u __DEPLOY_USER__ \
    -i infra/ansible/inventory/production.yml \
    infra/ansible/playbooks/dump_db.yml \
    -e "dump_env=$ENV_RAW" \
    -e "dump_db_name=$SOURCE_DB_NAME" \
    -e "dump_db_user=$SOURCE_DB_USER" \
    -e "dump_output_local=$TEMP_DUMP_FILE"

  if [[ ! -s "$TEMP_DUMP_FILE" ]]; then
    echo "Downloaded dump is empty. Aborting." >&2
    exit 1
  fi

  mv "$TEMP_DUMP_FILE" "$CACHED_DUMP_FILE"
  trap - EXIT
else
  echo "Reusing local dump: $CACHED_DUMP_FILE"
fi

if [[ ! -s "$CACHED_DUMP_FILE" ]]; then
  echo "Local dump file is missing or empty: $CACHED_DUMP_FILE" >&2
  exit 1
fi

LOCAL_DB_NAME="__APP_SLUG___development"

echo "Restoring into local database '$LOCAL_DB_NAME'..."
psql -d postgres -v ON_ERROR_STOP=1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$LOCAL_DB_NAME' AND pid <> pg_backend_pid();" >/dev/null
dropdb --if-exists "$LOCAL_DB_NAME"
createdb "$LOCAL_DB_NAME"
# Filter known cross-version SET incompatibility while preserving hard-fail for other SQL errors.
pg_restore \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  -f - \
  "$CACHED_DUMP_FILE" \
  | sed '/^SET transaction_timeout = 0;$/d' \
  | psql -d "$LOCAL_DB_NAME" -v ON_ERROR_STOP=1

echo "Local restore complete from '$ENV_RAW'."
