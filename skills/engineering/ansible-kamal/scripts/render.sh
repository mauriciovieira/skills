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
#   SECRET_CMD        absolute path to a command that prints a secret to stdout,
#                     with no arguments, e.g. '/usr/local/bin/secret'
#   SECRET_NAMESPACE  prefix for every secret name, e.g. infra/myapp
#   ENV_MODE          staging+production|single
#   TARGET_DIR        path to project root
#
# Optional:
#   DOMAIN_STAGING    required if ENV_MODE=staging+production; ignored otherwise
#   FORCE             1 to overwrite existing infra/ansible
#
# Usage:
#   APP_SLUG=… APP_SERVICE=… ... TARGET_DIR=. ~/.claude/skills/ansible-kamal/scripts/render.sh

set -euo pipefail

require() {
  local var="$1"
  if [[ -z "${!var:-}" || -z "${!var// /}" ]]; then
    echo "ERROR: required env var $var is empty or only whitespace" >&2
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

# SECRET_CMD is an absolute path to an executable, with no arguments. That is a
# narrow contract on purpose. The value is baked into a Makefile and into two
# /bin/sh scripts that run from different working directories, and five earlier
# attempts to allow anything looser each admitted a value that resolved to one
# file from the project root and another from infra/ansible - a relative path
# with or without a leading dot, a leading ~, a leading space, and a wrapper
# like `env FOO=bar bin/secret` that hides the real executable behind its own
# first word. An absolute path with no arguments does not resolve against the
# caller's directory, and it lets the generated scripts quote the expansion,
# which removes word splitting and globbing too. Anything more elaborate goes in
# a wrapper script, which the generated infra/kamal/README.md shows how to write.
case "$SECRET_CMD" in
  *[[:space:]]*)
    echo "ERROR: SECRET_CMD must not contain whitespace - no arguments, and no" >&2
    echo "       leading or trailing space. Put arguments inside a wrapper script" >&2
    echo "       and name the wrapper." >&2
    exit 2
    ;;
  *'$'*|*'`'*)
    echo "ERROR: SECRET_CMD must not contain '\$' or a backtick - a make recipe" >&2
    echo "       hands the value to /bin/sh, which expands both, while the" >&2
    echo "       generated scripts do not." >&2
    exit 2
    ;;
  # Do not delete this arm because it looks like noise in a guard about paths.
  # On Linux, /proc/self/cwd is a symlink the kernel re-resolves to whichever
  # process is reading it, at the moment it reads. So /proc/self/cwd/bin/secret
  # starts with a slash, passes every check above, and is still relative to the
  # caller's directory - the one thing this whole guard exists to prevent. Same
  # for /proc/self/fd/N, /proc/self/root and /proc/<pid>/cwd.
  #
  # This catches the ordinary spellings and the two trivial aliases. It does NOT
  # catch a path that reaches /proc the long way, such as /opt/../proc/self/cwd.
  # Closing that needs the path resolved on the machine that will run it, which
  # the renderer is not: it may be a macOS laptop with no /proc at all. The
  # guarantee here is "no accidental cwd-dependent path", not "provably none".
  /proc/*|//proc/*|/./proc/*)
    echo "ERROR: SECRET_CMD must not be under /proc - the kernel re-resolves" >&2
    echo "       paths like /proc/self/cwd against whichever process reads them," >&2
    echo "       so they are relative in disguise. Use a real path." >&2
    exit 2
    ;;
  /*) ;;
  *)
    echo "ERROR: SECRET_CMD must be an absolute path - it is invoked from the" >&2
    echo "       project root and from infra/ansible, which are different" >&2
    echo "       directories, so anything relative names two different files." >&2
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
