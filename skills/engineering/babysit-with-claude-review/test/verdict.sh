#!/usr/bin/env bash
# Exercises the Step 3 run-verdict rule from ../SKILL.md.
#
# That rule is the only executable logic in an otherwise prose skill, and it
# decides whether a PR may merge - so it gets a test. Run: bash verdict.sh
#
# Fixtures under fixtures/ are trimmed from real `gh run view --log` output
# (the tab-separated job/step/timestamp prefix is preserved, because the greps
# have to survive it). The blocked and renamed cases are synthetic: no real log
# of either was available.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$HERE/../SKILL.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Kept in sync with SKILL.md by the drift check below - edit both together.
verdict() {
  local log="$1" denials turns
  denials=$(grep -oE 'permission_denials_count"?[: ]+[0-9]+' "$log" \
            | grep -oE '[0-9]+$' | sort -rn | head -1)
  turns=$(grep -oE '"num_turns": *[0-9]+' "$log" \
          | grep -oE '[0-9]+$' | sort -rn | head -1)
  if [ -z "$denials" ] || [ -z "$turns" ]; then
    echo "CLOSED-UNVERIFIABLE"
  elif [ "$denials" -gt 0 ] && [ "$turns" -le 2 ]; then
    echo "CLOSED"
  elif [ "$denials" -gt 0 ]; then
    echo "FLAG"
  else
    echo "CLEAN"
  fi
}

# Synthetic cases.
# The documented blocked run: many denials, no real work, still exits green.
printf '"num_turns": 1,\n"permission_denials_count": 16,\n' > "$TMP/blocked.log"
# Upstream renames num_turns, so the grep silently stops matching.
printf '"numTurns": 10,\n"permission_denials_count": 0,\n' > "$TMP/renamed.log"

fail=0
check() {  # check <label> <expected> <log>
  local got; got=$(verdict "$3")
  if [ "$got" = "$2" ]; then
    printf 'ok   %-28s %s\n' "$1" "$got"
  else
    printf 'FAIL %-28s expected %s, got %s\n' "$1" "$2" "$got"
    fail=1
  fi
}

# run 33481585062 - authorised the merge of PR #11.
check "clean run"        CLEAN               "$HERE/fixtures/run-clean.log"
# run 33479917884 - 1 denial across 4 turns, a genuine clean review. Gating on
# denials > 0 alone would have wedged PR #11 on this run.
check "denials, real review" FLAG            "$HERE/fixtures/run-flagged.log"
check "denials, no work"     CLOSED          "$TMP/blocked.log"
check "result fields absent" CLOSED-UNVERIFIABLE "$TMP/renamed.log"

# The sticky surface is a verdict, not a finding: a clean review posts one too,
# so its body decides, never its existence.
sticky_verdict() {
  local body; body=$(cat "$1")
  if [ -z "$body" ]; then
    echo "ABSENT"
  elif printf '%s' "$body" | grep -qiE 'no issues found|found no issues'; then
    echo "CLEAN"
  else
    echo "CLOSED-UNREAD"
  fi
}

check_sticky() {  # check_sticky <label> <expected> <file>
  local got; got=$(sticky_verdict "$3")
  if [ "$got" = "$2" ]; then
    printf 'ok   %-28s %s\n' "$1" "$got"
  else
    printf 'FAIL %-28s expected %s, got %s\n' "$1" "$2" "$got"
    fail=1
  fi
}

: > "$TMP/sticky-absent.md"
# Real body from mauriciovieira/skills#14 - a clean review still posts a sticky.
check_sticky "sticky says clean"   CLEAN         "$HERE/fixtures/sticky-clean.md"
check_sticky "sticky has findings" CLOSED-UNREAD "$HERE/fixtures/sticky-findings.md"
check_sticky "no sticky this run"  ABSENT        "$TMP/sticky-absent.md"

# Drift check: the branch conditions above must still appear in SKILL.md. This
# is why the logic is duplicated rather than extracted - a copy that silently
# diverges from the doc would test nothing.
for cond in \
  '\[ -z "\$denials" \] \|\| \[ -z "\$turns" \]' \
  '\[ "\$denials" -gt 0 \] && \[ "\$turns" -le 2 \]' \
  "grep -qiE 'no issues found|found no issues'"
do
  if grep -qF "$(printf '%s' "$cond" | sed 's/\\//g')" "$SKILL"; then
    printf 'ok   %-28s present in SKILL.md\n' "drift check"
  else
    printf 'FAIL %-28s condition missing from SKILL.md: %s\n' "drift check" "$cond"
    fail=1
  fi
done

[ "$fail" -eq 0 ] && echo "all checks passed"
exit "$fail"
