#!/usr/bin/env bash
# Regression test for the ansible-kamal renderer.
#
# Run from anywhere: `bash skills/engineering/ansible-kamal/test/render.sh`.
# `control drive ansible-kamal` finds it because it is a *.sh under a test path
# inside the skill directory, and runs it from the repository root.
#
# What it defends: that rendering still produces a complete, parseable tree in
# both ENV_MODEs, that no placeholder and no secret-manager-specific string
# leaks into the output, and that every SECRET_CMD form the contract forbids is
# rejected at render time rather than failing later from one directory but not
# another.
set -uo pipefail

SKILL="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
check() {
    if [ "$1" = 0 ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n' "$2" >&2
    fi
}

# Render with the given ENV_MODE and SECRET_CMD into $1. Returns render.sh's exit code.
render() {
    out=$1 mode=$2 cmd=$3
    [ "$mode" = single ] && staging="" || staging=staging.example.com
    APP_SLUG=myapp APP_SERVICE=my-app APP_SLUG_UPPER=MYAPP INVENTORY_GROUP=myapp \
    VPS_IP=203.0.113.10 DOMAIN_PROD=example.com DOMAIN_STAGING="$staging" \
    LETSENCRYPT_EMAIL=admin@example.com DEPLOY_USER=myapp_deploy IMAGE_REPO=myorg/my-app \
    SECRET_CMD="$cmd" SECRET_NAMESPACE=infra/myapp ENV_MODE="$mode" TARGET_DIR="$out" \
    "$SKILL/scripts/render.sh" >/dev/null 2>&1
}

for mode in staging+production single; do
    d="$TMP/${mode//+/-}"
    mkdir -p "$d"

    render "$d" "$mode" /usr/local/bin/secret
    check $? "$mode: render.sh exits 0"

    grep -rlE '__[A-Z][A-Z0-9_]*__' "$d" >/dev/null 2>&1
    check $((1 - $?)) "$mode: no unsubstituted __PLACEHOLDER__ survives"

    # The renderer must not bake in any particular secret manager.
    grep -rniE 'pass show|pass insert|password-store|PASSWORD_STORE|PASS_CMD|__PASS' "$d" >/dev/null 2>&1
    check $((1 - $?)) "$mode: no secret-manager-specific string survives"

    bash -n "$d/scripts/kamal-deploy.sh" 2>/dev/null &&
        bash -n "$d/scripts/db-restore-from-vps.sh" 2>/dev/null
    check $? "$mode: both generated scripts parse"

    { [ -x "$d/scripts/kamal-deploy.sh" ] && [ ! -e "$d/scripts/kamal-deploy-from-pass.sh" ]; }
    check $? "$mode: kamal-deploy.sh is executable and the old name is gone"

    # An absolute path with no arguments can be quoted, which is what removes
    # word splitting and globbing. An unquoted $SECRET_CMD here would be a
    # silent wrong-file read.
    grep -q '"\$SECRET_CMD" "\$1"' "$d/scripts/kamal-deploy.sh" &&
        grep -q '"\$SECRET_CMD" "\$1"' "$d/scripts/db-restore-from-vps.sh"
    check $? "$mode: both generated scripts quote the SECRET_CMD expansion"

    # The make recipe hands the substituted value to /bin/sh, so it needs the
    # same quoting.
    grep -q '\$\$("\$(SECRET_CMD)"' "$d/infra/ansible/Makefile"
    check $? "$mode: the ansible recipe quotes the SECRET_CMD expansion"

    grep -q 'SECRET_CMD ?= /usr/local/bin/secret' "$d/infra/ansible/Makefile"
    check $? "$mode: ansible Makefile defaults SECRET_CMD to the rendered path"

    make -n -C "$d/infra/ansible" ansible 2>/dev/null |
        grep -q '"/usr/local/bin/secret" infra/myapp/postgres_myapp_prod_password'
    check $? "$mode: make expands the ansible recipe to the real command"

    make -n -C "$d" deploy ENV=production 2>/dev/null |
        grep -q 'SECRET_CMD="/usr/local/bin/secret".*./scripts/kamal-deploy.sh'
    check $? "$mode: root Makefile deploy passes SECRET_CMD to the renamed script"

    if [ "$mode" = single ]; then
        { [ ! -e "$d/config/deploy.staging.yml" ] && [ ! -e "$d/.kamal/secrets.staging" ] &&
            ! grep -q rails_master_key_staging "$d/scripts/kamal-deploy.sh"; }
        check $? "single: staging files and sentinel blocks are dropped"
    else
        { [ -e "$d/config/deploy.staging.yml" ] &&
            grep -q rails_master_key_staging "$d/scripts/kamal-deploy.sh"; }
        check $? "staging+production: staging files and sentinel blocks are kept"
    fi
done

# A wrapper documented in infra/kamal/README.md is copied verbatim and executed,
# so its shebang has to be on byte 0 or the kernel falls back to sh.
awk '/^```sh$/ { want = 1; next } want { print; exit }' \
    "$TMP/single/infra/kamal/README.md" | grep -q '^#!'
check $? "the wrapper example in kamal/README.md starts with its shebang"

# Every SECRET_CMD form that would resolve differently depending on the calling
# directory must be refused at render time, with exit 2.
reject() {
    d="$TMP/reject"
    rm -rf "$d"
    mkdir -p "$d"
    render "$d" single "$1"
    [ $? = 2 ]
    check $? "SECRET_CMD '$1' is rejected with exit 2"
}

accept() {
    d="$TMP/accept"
    rm -rf "$d"
    mkdir -p "$d"
    render "$d" single "$1"
    check $? "SECRET_CMD '$1' is accepted"
}

# Every form that five earlier rounds of review found slipping through some
# looser version of this guard. Each one resolves to a different file depending
# on which of the two call sites invokes it.
reject 'bin/secret'
reject './bin/secret'
reject '../bin/secret'
reject '~/bin/secret'
reject 'secret'
reject ' /usr/local/bin/secret'
reject '/usr/local/bin/secret '
reject '   '
reject 'env FOO=bar bin/secret'
reject '/usr/local/bin/secret --store infra/prod'
# make hands the value to /bin/sh inside double quotes, which expands both.
reject '/usr/local/bin/sec$ret'
reject '/usr/local/bin/sec`id`ret'

# The guard must not simply refuse everything.
accept /usr/local/bin/secret
accept /opt/vendor/bin/get-secret

# `require` used to accept a whitespace-only value, which then reached the
# templates and, in the ansible recipe, would have run the secret NAME as a
# command. Any required variable, not just SECRET_CMD.
d="$TMP/blank"
rm -rf "$d"
mkdir -p "$d"
APP_SLUG='   ' APP_SERVICE=my-app APP_SLUG_UPPER=MYAPP INVENTORY_GROUP=myapp \
VPS_IP=203.0.113.10 DOMAIN_PROD=example.com DOMAIN_STAGING= \
LETSENCRYPT_EMAIL=admin@example.com DEPLOY_USER=myapp_deploy IMAGE_REPO=myorg/my-app \
SECRET_CMD=/usr/local/bin/secret SECRET_NAMESPACE=infra/myapp ENV_MODE=single \
TARGET_DIR="$d" "$SKILL/scripts/render.sh" >/dev/null 2>&1
[ $? = 2 ]
check $? "a whitespace-only required variable is rejected with exit 2"

total=$((pass + fail))
if [ "$fail" = 0 ]; then
    echo "$pass/$total OK"
else
    echo "$pass/$total OK, $fail FAILED"
    exit 1
fi
