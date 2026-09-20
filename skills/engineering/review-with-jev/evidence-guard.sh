#!/usr/bin/env bash
# Deterministic path filter for the evidence package sent to the Jev API.
#
# The jev_review server sends exactly what the caller hands it. It does no
# redaction, no path exclusion and no size capping - verified by reading every
# file under upstream's src/. So this script is the only thing standing between
# a repository's secrets and a third-party API, and it is a script rather than
# a paragraph of prose because prose fails silently.
#
# Usage:  git diff --name-only <base>...HEAD | bash evidence-guard.sh
#         bash evidence-guard.sh path [path...]
#
# Prints one line per path: "include <path>" or "exclude <path> <reason>".
# Exclusions are printed, never dropped: a silent drop is indistinguishable
# from an oversight, and the caller has to report what it withheld.
#
# Exit 0 - nothing credential-shaped in the list.
# Exit 2 - at least one credential-shaped path. Loud on purpose.
#
# Feed it the working tree and untracked files too, not just the committed diff:
# a freshly dropped .env is untracked, which is the case this exists for.
#
# Kind is decided by path shape alone, so a repo where build/ or vendor/ holds real
# source will see those excluded. That is why every exclusion prints its reason:
# the caller can see the call and override it deliberately.
set -uo pipefail

kind_of() {
  local p="$1" base
  base="${p##*/}"

  # Credential-shaped path segments.
  case "/$p/" in
    */.ssh/*|*/.aws/*|*/.gnupg/*|*/secrets/*) echo secret; return ;;
  esac

  # Credential-shaped filenames. Sample/example/template env files are fine:
  # they exist to be read and carry no live value.
  case "$base" in
    *.example|*.sample|*.template) ;;
    .env|.env.*|*.env) echo secret; return ;;
  esac
  case "$base" in
    id_rsa|id_dsa|id_ecdsa|id_ed25519) echo secret; return ;;
    *.pem|*.p12|*.pfx|*.key|*.jks|*.keystore|*.kdbx) echo secret; return ;;
    .npmrc|.pypirc|.netrc|credentials.json|secrets.*) echo secret; return ;;
  esac

  case "/$p" in
    */node_modules/*|*/vendor/*|*/third_party/*|*/.venv/*|*/venv/*) echo vendored; return ;;
    */dist/*|*/build/*|*/.next/*|*/coverage/*|*/__pycache__/*) echo generated; return ;;
  esac

  case "$base" in
    *.min.js|*.min.css|*.map|*_pb2.py|*.pb.go|*.generated.*) echo generated; return ;;
    package-lock.json|yarn.lock|pnpm-lock.yaml|Cargo.lock|Gemfile.lock) echo lockfile; return ;;
    poetry.lock|composer.lock|go.sum|uv.lock) echo lockfile; return ;;
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico|*.pdf|*.zip|*.tar|*.gz) echo binary; return ;;
    *.mp4|*.mov|*.mp3|*.wav|*.woff|*.woff2|*.ttf|*.otf) echo binary; return ;;
    *.so|*.dylib|*.dll|*.exe|*.jar|*.wasm|*.db|*.sqlite|*.sqlite3) echo binary; return ;;
  esac

  echo include
}

reason_for() {
  case "$1" in
    secret)    echo "credential-shaped path" ;;
    binary)    echo "binary file" ;;
    vendored)  echo "vendored dependency" ;;
    generated) echo "generated output" ;;
    lockfile)  echo "lockfile" ;;
  esac
}

found_secret=0
handle() {
  local p="$1" kind
  [ -n "$p" ] || return 0
  # Skip decoration rather than classifying it as a file. No real path starts
  # with "-", and some git wrappers prefix their output with a header line.
  case "$p" in -*) return 0 ;; esac
  kind="$(kind_of "$p")"
  if [ "$kind" = include ]; then
    echo "include $p"
  else
    echo "exclude $p $(reason_for "$kind")"
    [ "$kind" = secret ] && found_secret=2
  fi
  return 0
}

if [ "$#" -gt 0 ]; then
  for p in "$@"; do handle "$p"; done
else
  while IFS= read -r p; do handle "$p"; done
fi

exit "$found_secret"
