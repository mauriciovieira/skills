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

# Every rule below describes a SHAPE, not a spelling. Bash `case` is
# case-sensitive and nocasematch is off by default, so each rule only ever
# fired on the exact lowercase form: `.env` was excluded while `.ENV`,
# `prod.Env`, `Credentials.json`, `Secrets.yaml`, `SECRETS/db.txt`, `ID_RSA`
# and `app.PEM` were all reported as include, and their contents went to the
# third-party API with the run reporting "declined". Because no rule fired, a
# list of only those also exited 0, so the one loud path stayed silent.
# Credentials.json and Secrets.json are ordinary .NET names and .ENV is what
# some Windows editors write - this was not an exotic case.
#
# Scope, stated honestly: this is global to the script, so it also widens the
# vendored, generated, lockfile and binary blocks below - `Build/`, `Vendor/`
# and `*.PNG` now match too. That is over-exclusion, which this file already
# accepts as the cheap side of the trade, and every exclusion prints its
# reason. The string tests in handle() use [ ], which is unaffected, so the
# include/exclude decision itself keeps its exact matching.
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
    # Unanchored on both sides: `-id_rsa` and `backup-id_rsa` hold exactly the
    # same private key as `id_rsa`, and a start-anchored pattern let both
    # through. Over-excluding a `docs/id_rsa-howto.md` costs one printed line
    # that the caller can see and override; under-excluding ships a key.
    *id_rsa*|*id_dsa*|*id_ecdsa*|*id_ed25519*) echo "$SECRET_REASON"; return ;;
    *.pem*|*.p12*|*.pfx*|*.key*|*.jks*) echo "$SECRET_REASON"; return ;;
    *.keystore*|*.kdbx*|*.p8*|*.ppk*) echo "$SECRET_REASON"; return ;;
    # Unanchored for the same reason as the keys above, and written out
    # because the first version of this line was not: `.pgpass` and
    # `.htpasswd` were exact matches, so backup.pgpass, db.pgpass.bak and
    # site.htpasswd.old all read as ordinary files. No dot either - Windows
    # spells it pgpass.conf, which even `*.pgpass*` would miss.
    *pgpass*|*htpasswd*|*.tfstate*) echo "$SECRET_REASON"; return ;;
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
  # Decoration from a git wrapper is reported as skipped, never dropped in
  # silence - the header promises nothing vanishes without a line.
  reason="$(classify "$p")"
  # Decoration is a DIFF MARKER, not any leading dash. Matching `-*` meant
  # `-prod.env` and `-id_rsa` printed "not a path", left found_secret at 0 and
  # exited the whole list clean: a file named with a dash disarmed the secret
  # gate. A leading dash is part of a filename far more often than it is a
  # wrapper's `--- Changes ---` banner.
  #
  # Two defences, because either alone still leaks. The narrow pattern stops a
  # single-dash filename being read as decoration; classifying first stops even
  # a `---prod.env` from being skipped, since nothing credential-shaped may be
  # skipped whatever it starts with.
  if [ "$reason" != "$SECRET_REASON" ]; then
    case "$p" in ---*|+++*|@@*) echo "skip $p not a path"; return 0 ;; esac
  fi
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
