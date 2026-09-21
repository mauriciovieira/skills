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
#   SECRET_CMD        command that prints a secret to stdout, e.g. 'secret'
#   SECRET_NAMESPACE  prefix for every secret name, e.g. infra/myapp
#   ENV_MODE          staging+production|single
#   TARGET_DIR        path to project root
#
# Optional:
#   DOMAIN_STAGING    required if ENV_MODE=staging+production; ignored otherwise
#   FORCE             1 to overwrite existing infra/ansible
#
# SECRET_CMD is split on whitespace to separate the command from its fixed
# arguments, so a command path containing a space cannot work. The guard below
# states the rest of the contract and enforces it.
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
require SECRET_CMD
require SECRET_NAMESPACE
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

# SECRET_CMD must resolve identically from every directory it is invoked from.
# The generated scripts cd to the project root; `make -C infra/ansible ansible`
# runs with its own directory as cwd. So: PATH command or absolute path.
#
# `$` and `~` are rejected anywhere in the string, arguments included, because a
# make recipe hands the value to /bin/sh, which expands both, while inside the
# generated scripts the value arrives through parameter expansion, after which
# neither is expanded. Same string, two meanings.
case "$SECRET_CMD" in
  *'$'*)
    echo "ERROR: SECRET_CMD must not contain '\$' - make and sh expand it differently." >&2
    echo "       Wrap the lookup in a script and name that script instead." >&2
    exit 2
    ;;
  *'~'*)
    echo "ERROR: SECRET_CMD must not contain '~' - a make recipe expands it," >&2
    echo "       the generated scripts do not. Use an absolute path." >&2
    exit 2
    ;;
esac

# The path rules apply to the command word only: a fixed argument may well
# contain a slash. Any command word containing a slash is resolved against the
# current directory and never searched for on PATH, so unless it is absolute it
# names two different files from the two call sites.
case "${SECRET_CMD%% *}" in
  /*) ;;
  */*)
    echo "ERROR: SECRET_CMD must not be a relative path - it is invoked from the" >&2
    echo "       project root and from infra/ansible, which are different directories." >&2
    echo "       Put the command on PATH, or give an absolute path." >&2
    exit 2
    ;;
esac

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
    -e "s${sep}__SECRET_NAMESPACE__${sep}${SECRET_NAMESPACE}${sep}g" \
    -e "s${sep}__SECRET_CMD__${sep}${SECRET_CMD}${sep}g"
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
  3. Generate deploy SSH key + DB password(s); store them under: $SECRET_NAMESPACE
  4. DNS A records → $VPS_IP for: $DOMAIN_PROD${DOMAIN_STAGING:+ $DOMAIN_STAGING}
  5. DEPLOY_SSH_KEY="\$($SECRET_CMD $SECRET_NAMESPACE/deploy_ssh_public_key)" make -C infra/ansible bootstrap
  6. make -C infra/ansible ansible
  7. Wire GitHub Environments + secrets per infra/kamal/README.md
  8. ENV=production make deploy$( [[ "$ENV_MODE" == "staging+production" ]] && echo "  (and ENV=staging make deploy)" )
EOF
