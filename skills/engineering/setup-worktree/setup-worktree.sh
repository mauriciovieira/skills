#!/usr/bin/env bash
# Set up a linked git worktree by symlinking dependency dirs and copying
# env files from the main repo. Language-agnostic: walks the main repo for
# known manifests and links each matching deps dir if it exists in main.
#
# Manifest -> deps dir candidates (first existing wins per manifest):
#   package.json     -> node_modules
#   pyproject.toml   -> .venv, venv, env
#   requirements.txt -> .venv, venv, env
#   Pipfile          -> .venv, venv, env
#   setup.py         -> .venv, venv, env
#   Gemfile          -> vendor/bundle, .bundle
#   go.mod           -> vendor
#   Cargo.toml       -> target
#   composer.json    -> vendor
#   mix.exs          -> deps, _build
#
# Env files copied (not linked): .env, .env.local, .env.development, .env.test
#
# Safety:
#   - refuses to run outside a linked worktree
#   - never overwrites existing files or links in the worktree
#   - skips deps dirs missing in main

set -euo pipefail

die() { printf 'setup-worktree: %s\n' "$*" >&2; exit 1; }
log() { printf 'setup-worktree: %s\n' "$*"; }

common_raw=$(git rev-parse --git-common-dir 2>/dev/null) || die "not in a git repository"
gitdir_raw=$(git rev-parse --git-dir 2>/dev/null)        || die "not in a git repository"
common=$(cd "$common_raw" && pwd -P)
gitdir=$(cd "$gitdir_raw" && pwd -P)
[ "$common" = "$gitdir" ] && die "not in a linked worktree (run from a worktree, e.g. .worktrees/<name>/)"

main=$(cd "$common/.." && pwd -P)
worktree=$(git rev-parse --show-toplevel)
worktree=$(cd "$worktree" && pwd -P)
[ "$main" = "$worktree" ] && die "main repo and worktree resolved to same path; aborting"

log "main repo: $main"
log "worktree:  $worktree"

PRUNE=( -path '*/node_modules' -o -path '*/.venv' -o -path '*/venv' -o -path '*/env' \
        -o -path '*/vendor' -o -path '*/target' -o -path '*/deps' -o -path '*/_build' \
        -o -path '*/.git' -o -path '*/.worktrees' -o -path '*/dist' -o -path '*/build' )

# --- Copy env files ---------------------------------------------------------
ENV_PATTERNS=( '.env' '.env.local' '.env.development' '.env.test' )

for pat in "${ENV_PATTERNS[@]}"; do
  while IFS= read -r src; do
    rel=${src#"$main"/}
    dst=$worktree/$rel
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      log "skip env $rel (exists in worktree)"
      continue
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    log "copied $rel"
  done < <(find "$main" -maxdepth 4 \( "${PRUNE[@]}" \) -prune -o -type f -name "$pat" -print)
done

# --- Symlink deps dirs ------------------------------------------------------
MANIFESTS=( 'package.json' 'pyproject.toml' 'requirements.txt' 'Pipfile' 'setup.py' 'Gemfile' 'go.mod' 'Cargo.toml' 'composer.json' 'mix.exs' )
DEPS_DIRS=( 'node_modules'
            '.venv venv env'
            '.venv venv env'
            '.venv venv env'
            '.venv venv env'
            'vendor/bundle .bundle'
            'vendor'
            'target'
            'vendor'
            'deps _build' )

linked_any=0
for i in "${!MANIFESTS[@]}"; do
  manifest=${MANIFESTS[$i]}
  candidates=${DEPS_DIRS[$i]}
  while IFS= read -r mfile; do
    parent=$(dirname "$mfile")
    rel=${parent#"$main"}
    rel=${rel#/}
    for dep in $candidates; do
      src=$parent/$dep
      if [ ! -e "$src" ] && [ ! -L "$src" ]; then continue; fi
      if [ -z "$rel" ]; then
        dst=$worktree/$dep
        rel_log=$dep
      else
        dst=$worktree/$rel/$dep
        rel_log=$rel/$dep
      fi
      if [ -e "$dst" ] || [ -L "$dst" ]; then
        log "skip $rel_log (exists in worktree)"
        continue
      fi
      mkdir -p "$(dirname "$dst")"
      ln -sfn "$src" "$dst"
      log "linked $rel_log -> $src"
      linked_any=1
    done
  done < <(find "$main" -maxdepth 4 \( "${PRUNE[@]}" \) -prune -o -type f -name "$manifest" -print)
done

if [ "$linked_any" -eq 0 ]; then
  log "no deps dirs linked (none found in main, or all already present)"
fi
log "done."
