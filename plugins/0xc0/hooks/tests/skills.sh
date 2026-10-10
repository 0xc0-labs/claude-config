#!/usr/bin/env bash
# Every SKILL.md of the plugin reaches a session as written. Claude Code
# replaces a bare $1, $2… in a skill with words of its arguments, so a
# snippet braces them, "${1}", or names them. A session's shell can be zsh,
# where arrays start at 1 and mapfile does not exist, so no snippet uses an
# array. Run by run.sh: first on a sample, whose marked lines must be caught
# and no other, then on every skill.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
n=0; failed=0

# A bare positional parameter, or an array: indexed, assigned or read into.
bad='\$[0-9]|\$\{#?[A-Za-z_][A-Za-z0-9_]*\[|[A-Za-z_][A-Za-z0-9_]*\+?=\(|mapfile|readarray|(declare|local|typeset|read) -[A-Za-z]*[aA]'
fail() { failed=$((failed + 1)); echo "FAIL [skills/$1] $2"; }
lines() { tr '\n' ' ' | sed 's/ $//'; }

n=$((n + 1))
want="$(grep -n ' # bad$' "$here/skill-sample.md" | cut -d: -f1 | lines)"
got="$(grep -nE "$bad" "$here/skill-sample.md" | cut -d: -f1 | lines)"
[ "$want" = "$got" ] || fail sample "caught lines '$got', want '$want'"

found=0
for skill in "$here"/../../skills/*/SKILL.md; do
  [ -f "$skill" ] || continue
  found=1; n=$((n + 1))
  name="$(basename "$(dirname "$skill")")"
  hits="$(grep -nE "$bad" "$skill")"
  [ -z "$hits" ] || fail "$name" "would not survive in a session:
$(sed 's/^/  /' <<<"$hits")"
done
[ "$found" -eq 1 ] || { n=$((n + 1)); fail none "no SKILL.md under skills/"; }

echo "$((n - failed))/$n skill cases pass"
[ "$failed" -eq 0 ]
