#!/usr/bin/env bash
# Render ansible-kamal templates into a target project.
# Reads required inputs from environment, walks templates/, applies placeholder substitution
# and staging/single sentinel block stripping, then writes to TARGET_DIR.
#
# Required env vars:
#   APP_SLUG          snake_case, e.g. myapp
#   APP_SERVICE       kebab-case, e.g. myapp
#   APP_SLUG_UPPER    e.g. MYAPP
#   INVENTORY_GROUP   e.g. myapp
#   VPS_IP            IPv4 of the VPS
#   DOMAIN_PROD       e.g. example.com
#   LETSENCRYPT_EMAIL e.g. admin@example.com
#   DEPLOY_USER       e.g. myapp_deploy
#   IMAGE_REPO        e.g. myorg/myapp
#   PASS_BACKEND      custom|pass
#   PASS_NAMESPACE    e.g. infra/myapp
#   ENV_MODE          staging+production|single
#   TARGET_DIR        path to project root
#
# Optional:
#   DOMAIN_STAGING    required if ENV_MODE=staging+production; ignored otherwise
#   PASS_STORE_DIR    e.g. '$(HOME)/.password-store-custom'  (Makefile-form, used as-is)
#   FORCE             1 to overwrite existing infra/ansible
#
# Usage:
#   APP_SLUG=… APP_SERVICE=… ... TARGET_DIR=. ~/.claude/skills/ansible-kamal/scripts/render.sh

set -euo pipefail

require() {
  local var="$1"
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: required env var $var is empty" >&2
    exit 2
  fi
}

require APP_SLUG
require APP_SERVICE
require APP_SLUG_UPPER
require INVENTORY_GROUP
require VPS_IP
require DOMAIN_PROD
require LETSENCRYPT_EMAIL
require DEPLOY_USER
require IMAGE_REPO
require PASS_BACKEND
require PASS_NAMESPACE
require ENV_MODE
require TARGET_DIR

case "$ENV_MODE" in
  staging+production)
    require DOMAIN_STAGING
    ;;
  single)
    DOMAIN_STAGING="${DOMAIN_STAGING:-}"
    ;;
  *)
    echo "ERROR: ENV_MODE must be 'staging+production' or 'single'" >&2
    exit 2
    ;;
esac

case "$PASS_BACKEND" in
  custom)
    PASS_STORE_DIR_DEFAULT='$(HOME)/.password-store-custom'
    PASS_STORE_DIR_SHELL_DEFAULT="$HOME/.password-store-custom"
    PASS_CMD_DEFAULT='env PASSWORD_STORE_DIR=$(HOME)/.password-store-custom pass'
    ;;
  pass)
    PASS_STORE_DIR_DEFAULT='$(HOME)/.password-store'
    PASS_STORE_DIR_SHELL_DEFAULT="$HOME/.password-store"
    PASS_CMD_DEFAULT='pass'
    ;;
  *)
    echo "ERROR: PASS_BACKEND must be 'custom' or 'pass'" >&2
    exit 2
    ;;
esac

PASS_STORE_DIR_RAW="${PASS_STORE_DIR:-$PASS_STORE_DIR_DEFAULT}"
PASS_STORE_DIR_SHELL="${PASS_STORE_DIR_SHELL:-$PASS_STORE_DIR_SHELL_DEFAULT}"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES_DIR="$SKILL_DIR/templates"
TARGET_DIR_ABS="$(cd "$TARGET_DIR" && pwd)"

if [[ -d "$TARGET_DIR_ABS/infra/ansible" && "${FORCE:-0}" != "1" ]]; then
  echo "ERROR: $TARGET_DIR_ABS/infra/ansible already exists. Set FORCE=1 to overwrite." >&2
  exit 3
fi

# Strip sentinel blocks. Always passes through input even when no sentinels are present.
# In ENV_MODE=staging+production: keep staging-only blocks, drop single-only blocks.
# In ENV_MODE=single:              drop staging-only blocks, keep single-only blocks.
strip_sentinels() {
  awk -v mode="$ENV_MODE" '
    BEGIN { skip = 0 }
    /(^|[^A-Za-z0-9_])>>>[[:space:]]*staging-only([^A-Za-z0-9_]|$)/ {
      if (mode == "single") { skip = 1 }
      next
    }
    /(^|[^A-Za-z0-9_])<<<[[:space:]]*staging-only([^A-Za-z0-9_]|$)/ {
      skip = 0
      next
    }
    /(^|[^A-Za-z0-9_])>>>[[:space:]]*single-only([^A-Za-z0-9_]|$)/ {
      if (mode == "staging+production") { skip = 1 }
      next
    }
    /(^|[^A-Za-z0-9_])<<<[[:space:]]*single-only([^A-Za-z0-9_]|$)/ {
      skip = 0
      next
    }
    !skip { print }
  '
}

# Substitute __VAR__ placeholders. We use a sentinel character (\x01) as sed delimiter so values
# can contain slashes, dollar signs, and parens without escaping.
substitute_vars() {
  local sep=$'\x01'
  sed \
    -e "s${sep}__APP_SLUG__${sep}${APP_SLUG}${sep}g" \
    -e "s${sep}__APP_SERVICE__${sep}${APP_SERVICE}${sep}g" \
    -e "s${sep}__APP_SLUG_UPPER__${sep}${APP_SLUG_UPPER}${sep}g" \
    -e "s${sep}__INVENTORY_GROUP__${sep}${INVENTORY_GROUP}${sep}g" \
    -e "s${sep}__VPS_IP__${sep}${VPS_IP}${sep}g" \
    -e "s${sep}__DOMAIN_PROD__${sep}${DOMAIN_PROD}${sep}g" \
    -e "s${sep}__DOMAIN_STAGING__${sep}${DOMAIN_STAGING}${sep}g" \
    -e "s${sep}__LETSENCRYPT_EMAIL__${sep}${LETSENCRYPT_EMAIL}${sep}g" \
    -e "s${sep}__DEPLOY_USER__${sep}${DEPLOY_USER}${sep}g" \
    -e "s${sep}__IMAGE_REPO__${sep}${IMAGE_REPO}${sep}g" \
    -e "s${sep}__PASS_NAMESPACE__${sep}${PASS_NAMESPACE}${sep}g" \
    -e "s${sep}__PASS_STORE_DIR_RAW__${sep}${PASS_STORE_DIR_RAW}${sep}g" \
    -e "s${sep}__PASS_STORE_DIR_SHELL__${sep}${PASS_STORE_DIR_SHELL}${sep}g" \
    -e "s${sep}__PASS_CMD_DEFAULT__${sep}${PASS_CMD_DEFAULT}${sep}g"
}

should_skip_path() {
  local rel="$1"
  if [[ "$ENV_MODE" == "single" ]]; then
    case "$rel" in
      *config/deploy.staging.yml|*.kamal/secrets.staging)
        return 0
        ;;
    esac
  fi
  return 1
}

count_in=0
count_out=0
count_skip=0

while IFS= read -r -d '' abs; do
  rel="${abs#$TEMPLATES_DIR/}"
  count_in=$((count_in + 1))
  if should_skip_path "$rel"; then
    count_skip=$((count_skip + 1))
    continue
  fi
  src="$abs"
  dest="$TARGET_DIR_ABS/$rel"
  mkdir -p "$(dirname "$dest")"
  strip_sentinels <"$src" | substitute_vars >"$dest"
  if [[ -x "$src" ]]; then
    chmod +x "$dest"
  fi
  count_out=$((count_out + 1))
done < <(find "$TEMPLATES_DIR" -type f -print0)

# Make scripts executable regardless of source perms (find on macOS/Linux can lose +x via copy).
[[ -d "$TARGET_DIR_ABS/scripts" ]] && chmod +x "$TARGET_DIR_ABS"/scripts/*.sh 2>/dev/null || true

cat <<EOF
ansible-kamal: rendered $count_out file(s) into $TARGET_DIR_ABS
  templates seen: $count_in
  skipped (mode=$ENV_MODE): $count_skip

Next steps:
  1. Review generated files (git status / git diff).
  2. cd infra/ansible && make setup && make test
  3. Generate deploy SSH key + DB password(s); store in pass under: $PASS_NAMESPACE
  4. DNS A records → $VPS_IP for: $DOMAIN_PROD${DOMAIN_STAGING:+ $DOMAIN_STAGING}
  5. DEPLOY_SSH_KEY="\$(pass show $PASS_NAMESPACE/deploy_ssh_public_key)" make -C infra/ansible bootstrap
  6. make -C infra/ansible ansible
  7. Wire GitHub Environments + secrets per infra/kamal/README.md
  8. ENV=production make deploy$( [[ "$ENV_MODE" == "staging+production" ]] && echo "  (and ENV=staging make deploy)" )
EOF
