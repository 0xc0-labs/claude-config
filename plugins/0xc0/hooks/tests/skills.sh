#!/usr/bin/env bash
# Why each pattern would not survive in a session: the README, Skills.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
n=0; failed=0

bad='\$[0-9]|\$\{#?[A-Za-z_][A-Za-z0-9_]*\[|[A-Za-z_][A-Za-z0-9_]*\+?=\(|mapfile|readarray|(declare|local|typeset|read) -[A-Za-z]*[aA]|\$\(([^)]*[^A-Za-z0-9_.-])?git[[:space:]]'
fail() { failed=$((failed + 1)); echo "FAIL [$1] $2"; }
lines() { tr '\n' ' ' | sed 's/ $//'; }

n=$((n + 1))
want="$(grep -n ' # bad$' "$here/skill-sample.md" | cut -d: -f1 | lines)"
got="$(grep -nE "$bad" "$here/skill-sample.md" | cut -d: -f1 | lines)"
[ "$want" = "$got" ] || fail skills/sample "caught lines '$got', want '$want'"

found=0
for skill in "$here"/../../skills/*/SKILL.md; do
  [ -f "$skill" ] || continue
  found=1; n=$((n + 1))
  name="$(basename "$(dirname "$skill")")"
  hits="$(grep -nE "$bad" "$skill")"
  [ -z "$hits" ] || fail "skills/$name" "would not survive in a session:
$(sed 's/^/  /' <<<"$hits")"
done
[ "$found" -eq 1 ] || { n=$((n + 1)); fail skills/none "no SKILL.md under skills/"; }

for ref in "$here"/../../references/*.md; do
  [ -f "$ref" ] || continue
  n=$((n + 1))
  hits="$(grep -nE "$bad" "$ref")"
  [ -z "$hits" ] || fail "references/$(basename "$ref")" "would not survive in a session:
$(sed 's/^/  /' <<<"$hits")"
done

echo "$((n - failed))/$n skill cases pass"
[ "$failed" -eq 0 ]
