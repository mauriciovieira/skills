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
set -u

# Every rule below describes a SHAPE, not a spelling, so the matching must not
# care about case. Bash `case` is case-sensitive and nocasematch is off by
# default, which meant the rules only ever fired on the exact lowercase form:
# `.env` was excluded while `.ENV`, `Credentials.json`, `Secrets.yaml`,
# `SECRETS/db.txt`, `ID_RSA` and `app.PEM` were all reported as include, and
# their contents went to the third-party API with the run printing "declined".
# Worse, a list containing only those never tripped exit 2, so the one loud
# path stayed silent. Credentials.json and Secrets.json are ordinary .NET
# names and .ENV is what some Windows editors write, so this was not exotic.
#
# This affects `case` only. The two string tests in handle() use [ ], which is
# unaffected, so the include/exclude decision itself keeps its exact matching.
shopt -s nocasematch

SECRET_REASON="credential-shaped path"

# Echoes the exclusion reason, or "include". One switch, not two: an earlier
# version returned a bare kind that a second switch re-mapped to this prose.
classify() {
  local p="$1" base
  base="${p##*/}"

  case "/$p/" in
    */.ssh/*|*/.aws/*|*/.gnupg/*) echo "$SECRET_REASON"; return ;;
    */secrets/*|*.secrets/*) echo "$SECRET_REASON"; return ;;
  esac

  # Sample/example/template env files are fine: they exist to be read and hold
  # no live value. The carve-out stops at the .env family on purpose - a file
  # called secrets.db.example stays excluded, because over-excluding costs one
  # printed line and under-excluding ships a credential to a third party.
  case "$base" in
    *.example|*.sample|*.template) ;;
    .env|.env.*|*.env|.envrc) echo "$SECRET_REASON"; return ;;
  esac

  # Matched with the prefixes AND trailing suffixes these files carry in the
  # wild: prod.credentials.json, credentials.json.bak, app.npmrc, id_rsa.old,
  # config.pem.example. Anchoring on the last extension was a leak - any
  # trailing suffix defeated it, and ".example" on a key file reads as safe to
  # a human skimming the output while the file can still hold a live key.
  # The .env family above is the one deliberate carve-out: it is a documented,
  # ubiquitous convention. Nothing else gets one.
  case "$base" in
    id_rsa*|id_dsa*|id_ecdsa*|id_ed25519*) echo "$SECRET_REASON"; return ;;
    *.pem*|*.p12*|*.pfx*|*.key*|*.jks*) echo "$SECRET_REASON"; return ;;
    *.keystore*|*.kdbx*|*.p8*|*.ppk*) echo "$SECRET_REASON"; return ;;
    .pgpass|.htpasswd|*.tfstate*) echo "$SECRET_REASON"; return ;;
    *npmrc*|*pypirc*|*netrc*) echo "$SECRET_REASON"; return ;;
    *credentials|*credentials.*) echo "$SECRET_REASON"; return ;;
    secrets|secrets.*|*.secrets|*.secrets.*) echo "$SECRET_REASON"; return ;;
  esac

  case "/$p" in
    */node_modules/*|*/vendor/*|*/third_party/*|*/.venv/*|*/venv/*) echo "vendored dependency"; return ;;
    */dist/*|*/build/*|*/.next/*|*/coverage/*|*/__pycache__/*) echo "generated output"; return ;;
  esac

  case "$base" in
    *.min.js|*.min.css|*.map|*_pb2.py|*.pb.go|*.generated.*) echo "generated output"; return ;;
    package-lock.json|yarn.lock|pnpm-lock.yaml|Cargo.lock|Gemfile.lock) echo lockfile; return ;;
    poetry.lock|composer.lock|go.sum|uv.lock) echo lockfile; return ;;
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico|*.pdf|*.zip|*.tar|*.gz) echo "binary file"; return ;;
    *.mp4|*.mov|*.mp3|*.wav|*.woff|*.woff2|*.ttf|*.otf) echo "binary file"; return ;;
    *.so|*.dylib|*.dll|*.exe|*.jar|*.wasm|*.db|*.sqlite|*.sqlite3) echo "binary file"; return ;;
  esac

  echo include
}

found_secret=0
handle() {
  local p="$1" reason
  [ -n "$p" ] || return 0
  # A leading dash is a filename, not decoration. Skipping it left the secret
  # gate disarmed: `-prod.env` was reported as "not a path", found_secret
  # stayed 0, and the caller escalated on nothing. Callers pass paths after
  # `--`, so git cannot read one as an option either.
  reason="$(classify "$p")"
  if [ "$reason" = include ]; then
    echo "include $p"
  else
    echo "exclude $p $reason"
    if [ "$reason" = "$SECRET_REASON" ]; then found_secret=2; fi
  fi
}

if [ "$#" -gt 0 ]; then
  for p in "$@"; do handle "$p"; done
else
  while IFS= read -r p; do handle "$p"; done
fi

exit "$found_secret"
