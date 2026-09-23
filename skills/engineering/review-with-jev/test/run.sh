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

# The same question, asked of every other family. The block above caught the
# anchoring bug for id_rsa and nothing asked it of pgpass or htpasswd, so a
# first version of this commit shipped them as exact matches: backup.pgpass,
# db.pgpass.bak and site.htpasswd.old all read as ordinary files while 95/95
# passed. A rule tested only at its literal spelling is a rule tested nowhere.
for p in \
  backup.pgpass db.pgpass.bak pgpass.conf \
  site.htpasswd.old team.htpasswd.bak \
  prod.tfstate.backup old.p8.bak deploy.ppk.old \
  vault.kdbx.bak app.keystore.old
do
  check "unanchored family: $p" "exclude $p credential-shaped path" "$(verdict "$p")"
done

# --- the .env family, unanchored like every other ---------------------------
# This family was the one left anchored at the end when everything else was
# unanchored - and it is the family lines 20-21 name as the reason this script
# exists. .orig is what a conflicted merge leaves behind; .bak and .old are
# what a human leaves; dev.env~ is what emacs, gedit and vim leave, and an
# `.env` line in .gitignore does not cover it, so it survives to reach here.
for p in production.env.bak config.env.backup prod.env.old staging.env.orig \
         'dev.env~' '.env '
do
  check "env suffix: $p" "exclude $p credential-shaped path" "$(verdict "$p")"
done

# The carve-out has to survive the widening, or every sample file gets withheld.
for p in .env.example prod.env.example config.env.sample
do
  check "env sample still ok: $p" "include $p" "$(verdict "$p")"
done

# `*.env.*` and not `*.env*`, because the wide form eats these.
for p in src/environment.ts src/dotenv.parser.ts
do
  check "env lookalike: $p" "include $p" "$(verdict "$p")"
done

# --- git quotes paths, and the quote lands where the rules are anchored -----
# core.quotePath defaults to true, so any path with a byte over 0x7F, a quote,
# a backslash or a control character arrives wrapped. The trailing " then sits
# at the end of the basename and defeats every end-anchored rule. An accented
# directory is ordinary in a Portuguese repo. The path must still be PRINTED
# exactly as git gave it - the caller needs those bytes to open the file.
quoted='"configura\303\247\303\243o/.env"'
check "quoted path excluded" "exclude $quoted credential-shaped path" "$(verdict "$quoted")"
quoted2='"configura\303\247\303\243o/credentials"'
check "quoted credentials" "exclude $quoted2 credential-shaped path" "$(verdict "$quoted2")"
bash "$GUARD" src/main.ts "$quoted" >/dev/null 2>&1
check "quoted path exits 2" "2" "$?"

# --- a credential directory, not just a credential basename -----------------
# credentials/service-account.json is the stock GCP layout; the basename rule
# only ever saw "service-account.json".
for p in credentials/prod.json config/credentials/db.yml credentials/service-account.json
do
  check "credential dir: $p" "exclude $p credential-shaped path" "$(verdict "$p")"
done

# --- stdin with no trailing newline -----------------------------------------
# `read` returns non-zero at EOF on an unterminated final line, so without the
# `|| [ -n "$p" ]` guard the last path is dropped in silence: nothing printed,
# found_secret untouched, exit 0. That breaks this file's own promise that
# exclusions are printed, never dropped.
out="$(printf 'src/a.ts\n.env' | bash "$GUARD" 2>/dev/null)"
check "stdin, no final newline" "include src/a.ts
exclude .env credential-shaped path" "$out"
printf 'src/a.ts\n.env' | bash "$GUARD" >/dev/null 2>&1
check "stdin no-newline exits 2" "2" "$?"

# --- the cost of nocasematch, recorded rather than discovered ---------------
# Making every rule case-insensitive also catches ordinary source whose name
# happens to be a credential word: Credentials.cs and Secrets.cs are .NET
# source, Config.Keys.ts is a TypeScript constant module. They are WITHHELD.
# That is over-exclusion, the side of the trade this file accepts, and each one
# prints its reason so the caller can see the call and override it - but the
# file under review can vanish from the evidence package this way, so the
# behaviour is pinned here instead of being rediscovered as a surprise.
for p in src/Credentials.cs src/Secrets.cs Auth/Credentials.razor src/Config.Keys.ts
do
  check "nocasematch cost: $p" "exclude $p credential-shaped path" "$(verdict "$p")"
done

# --- one path in, exactly one line out --------------------------------------
# verdict() reads only the first line, so a guard that printed two lines for
# one path would pass every other assertion in this file. jev-triage balances
# include + exclude against the number of paths it sent, so a duplicated line
# is exactly the failure worth catching.
for p in .env src/app.ts vendor/x.go
do
  n=$(bash "$GUARD" "$p" 2>/dev/null | wc -l | tr -d ' ')
  check "one line for $p" "1" "$n"
done

# --- whitespace and quotes, beyond a single trailing space ------------------
# The first normaliser stripped one balanced quote pair and then literal
# spaces, in that order. Everything else got through, and a file named
# `.env<TAB>` reached the outbound payload while the run reported "declined".
# `".env\t"` is what git emits under core.quotePath for a real tab: the two
# characters backslash and t, which no whitespace trim can reach.
for p in '.env	' '.env"' '"".env""' '".env" ' '".env\t"' '".env"'
do
  check "normalised: [$p]" "exclude $p credential-shaped path" "$(verdict "$p")"
done
bash "$GUARD" src/main.ts '.env	' >/dev/null 2>&1
check "tabbed secret exits 2" "2" "$?"
bash "$GUARD" src/main.ts '.env"' >/dev/null 2>&1
check "quoted secret exits 2" "2" "$?"
# Stripping must never eat a legitimate name, nor reduce one to nothing.
for p in 'a"b.py' src/environment.ts src/dotenv.parser.ts
do
  check "normalise keeps: $p" "include $p" "$(verdict "$p")"
done

# --- the .envrc family, unanchored like the rest ----------------------------
# .envrc was the one member left exact-anchored while the comment above it
# claimed the family had been unanchored. .envrc.local is a direnv convention
# and .envrc~ is the same editor backup `*.env~` exists for.
for p in .envrc .envrc.local .envrc.bak '.envrc~' dev.envrc
do
  check "envrc: $p" "exclude $p credential-shaped path" "$(verdict "$p")"
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
