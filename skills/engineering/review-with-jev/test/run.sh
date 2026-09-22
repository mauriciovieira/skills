#!/usr/bin/env bash
# Exercises evidence-guard.sh, the only executable logic in ../SKILL.md.
#
# It decides what leaves the machine for a third-party API, so it gets a test.
# `control drive review-with-jev` runs this. Run standalone: bash test/run.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/../evidence-guard.sh"
SKILL="$HERE/../SKILL.md"
pass=0; fail=0

check() { # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"
  fi
}

verdict() { bash "$GUARD" "$1" 2>/dev/null | head -1; }

# --- credential-shaped paths are excluded, and named ------------------------
for p in \
  .env \
  .env.local \
  config/production.env \
  .ssh/config \
  app/.aws/credentials \
  deploy/secrets/db.yml \
  keys/id_rsa \
  certs/server.pem \
  certs/tls.key \
  store/vault.kdbx \
  .npmrc \
  .netrc \
  credentials.json \
  secrets.yaml
do
  check "secret: $p" "exclude $p credential-shaped path" "$(verdict "$p")"
done

# Real-world prefixed and suffixed variants. Exact-basename matching let every
# one of these through as "include" until the Standards review caught it.
for p in \
  prod.credentials.json \
  credentials.json.bak \
  service-account-credentials.json \
  app.npmrc \
  build.netrc \
  id_rsa.bak \
  id_ed25519.old \
  deploy.secrets.json
do
  check "variant: $p" "exclude $p credential-shaped path" "$(verdict "$p")"
done

# A trailing suffix must not defeat the match. ".example" on a key file reads
# as safe to a human skimming the output, and the file can still hold a live
# key - so only the .env family gets the sample carve-out, nothing else.
for p in \
  config.pem.example \
  my_key.pem.sample \
  server.key.template \
  keystore.jks.bak \
  .npmrc.example \
  .secrets/prod.yml \
  team.secrets/db.yml
do
  check "suffixed: $p" "exclude $p credential-shaped path" "$(verdict "$p")"
done

# Ordinary source that merely rhymes with a credential must still pass.
for p in src/monkey.ts src/keyboard.ts src/secretsManager.ts src/credentialsProvider.ts
do
  check "not secret: $p" "include $p" "$(verdict "$p")"
done

# A credential-shaped path must also make the script exit loudly.
bash "$GUARD" src/main.ts .env >/dev/null 2>&1
check "secret sets exit 2" "2" "$?"

# --- every rule is a SHAPE, not a spelling ----------------------------------
# `case` is case-sensitive and nocasematch is off by default, so each rule used
# to fire only on the exact lowercase form. Credentials.json and Secrets.json
# are ordinary .NET names; .ENV is what some Windows editors write.
for p in \
  .ENV \
  prod.Env \
  config/.Env.production \
  Credentials.json \
  Secrets.yaml \
  SECRETS/db.txt \
  ID_RSA \
  app.PEM \
  Store/Vault.KDBX \
  .NPMRC
do
  check "uppercase: $p" "exclude $p credential-shaped path" "$(verdict "$p")"
done

# The carve-out has to be case-insensitive too, or it stops working the moment
# the rules above start ignoring case.
for p in .ENV.EXAMPLE Config.Env.Sample .Env.Template
do
  check "uppercase sample: $p" "include $p" "$(verdict "$p")"
done

# Capitals must not make ordinary source look credential-shaped either.
for p in KEYBOARD.md src/MonkeyPatch.ts docs/Credentials-Guide.md src/Keys.rs
do
  check "uppercase ok: $p" "include $p" "$(verdict "$p")"
done

# --- families that had no rule at all ---------------------------------------
for p in .envrc .pgpass .htpasswd terraform.tfstate infra.tfstate.backup \
         AuthKey_ABC123.p8 deploy.ppk
do
  check "family: $p" "exclude $p credential-shaped path" "$(verdict "$p")"
done

# --- a leading dash is a filename, not decoration ---------------------------
# Matching `-*` as decoration meant these printed "not a path" and left
# found_secret at 0, so the whole list exited clean. That is worse than leaking
# one file: it disarms the gate, and a caller reading only the exit code cannot
# tell "nothing suspicious" from "there was a secret and I skipped it".
for p in -prod.env -id_rsa ---prod.env
do
  check "dash: $p" "exclude $p credential-shaped path" "$(verdict "$p")"
done
check "dash, ordinary file" "include -normal.py" "$(verdict "-normal.py")"

# A key is the same key whatever sits in front of its name.
for p in backup-id_rsa my.id_ed25519.bak
do
  check "unanchored key: $p" "exclude $p credential-shaped path" "$(verdict "$p")"
done

# --- the EXIT CODE, not just the printed lines ------------------------------
# Both holes showed up here first. A test comparing only stdout passes with the
# gate wide open, because the lines can be right while the code says clean.
bash "$GUARD" src/main.ts .ENV >/dev/null 2>&1
check "uppercase secret exits 2" "2" "$?"
bash "$GUARD" src/main.ts -prod.env >/dev/null 2>&1
check "dash secret exits 2" "2" "$?"
bash "$GUARD" src/main.ts .envrc >/dev/null 2>&1
check "envrc exits 2" "2" "$?"
bash "$GUARD" src/main.ts README.md >/dev/null 2>&1
check "clean list exits 0" "0" "$?"
# Decoration alone must not be mistaken for a finding.
printf -- '--- Changes ---\nsrc/a.ts\n' | bash "$GUARD" >/dev/null 2>&1
check "decoration exits 0" "0" "$?"

# --- sample env files are readable, not secret ------------------------------
for p in .env.example .env.sample .env.template
do
  check "sample: $p" "include $p" "$(verdict "$p")"
done

# --- other excluded kinds carry their own reason ----------------------------
check "vendored"  "exclude node_modules/left-pad/index.js vendored dependency" \
                  "$(verdict node_modules/left-pad/index.js)"
check "vendored2" "exclude vendor/bundle/gem.rb vendored dependency" \
                  "$(verdict vendor/bundle/gem.rb)"
check "generated" "exclude dist/app.js generated output"  "$(verdict dist/app.js)"
check "generated2" "exclude src/api_pb2.py generated output" "$(verdict src/api_pb2.py)"
check "lockfile"  "exclude pnpm-lock.yaml lockfile"       "$(verdict pnpm-lock.yaml)"
check "lockfile2" "exclude go.sum lockfile"               "$(verdict go.sum)"
check "binary"    "exclude docs/diagram.png binary file"  "$(verdict docs/diagram.png)"
check "binary2"   "exclude lib/native.so binary file"     "$(verdict lib/native.so)"

# --- ordinary source, tests and docs go through -----------------------------
for p in src/auth/session.ts test/auth.spec.ts README.md docs/adr/0003-x.md \
         Makefile config/routes.rb .github/workflows/ci.yml
do
  check "include: $p" "include $p" "$(verdict "$p")"
done

# A path that merely mentions a keyword is not credential-shaped.
check "not secret: src/secretsManager.ts" "include src/secretsManager.ts" \
      "$(verdict src/secretsManager.ts)"
check "not secret: src/credentialsProvider.ts" "include src/credentialsProvider.ts" \
      "$(verdict src/credentialsProvider.ts)"

# --- decoration from git wrappers is skipped, not classified ----------------
out="$(printf -- '--- Changes ---\nsrc/a.ts\n' | bash "$GUARD" 2>/dev/null)"
check "decoration reported, not dropped" "skip --- Changes --- not a path
include src/a.ts" "$out"

# --- stdin mode matches argument mode ---------------------------------------
out="$(printf 'src/a.ts\n.env\n' | bash "$GUARD" 2>/dev/null)"
check "stdin lines" "include src/a.ts
exclude .env credential-shaped path" "$out"

# --- drift: the SKILL.md must still tell the agent to run this --------------
grep -q 'evidence-guard.sh' "$SKILL"
check "SKILL.md references the guard" "0" "$?"
grep -q 'JEV_API_KEY' "$SKILL"
check "SKILL.md names the env var" "0" "$?"
grep -q 'review-with-jev-policy@1' "$SKILL"
check "SKILL.md versions its policy" "0" "$?"

# The stopping rule must not key off the score. Real validation put correctness at
# 7.8 and security at 7.9 after a fix, which a ">= 8" rule would have kept looping on.
grep -q 'never a target to reach' "$SKILL"
check "stop rule does not chase the score" "0" "$?"

total=$((pass + fail))
if [ "$fail" -eq 0 ]; then
  echo "$pass/$total OK"
else
  echo "$pass/$total OK, $fail FAILED"
fi
exit "$([ "$fail" -eq 0 ] && echo 0 || echo 1)"
