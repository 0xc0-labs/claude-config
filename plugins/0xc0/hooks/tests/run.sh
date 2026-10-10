#!/usr/bin/env bash
# Runs every case in cases.jsonl through its hook and compares the exit code:
# 2 is blocked, 0 is allowed. Usage: plugins/0xc0/hooks/tests/run.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
n=0; failed=0
while IFS= read -r case; do
  [ -z "$case" ] && continue
  n=$((n + 1))
  hook="$(jq -r .hook <<<"$case")"
  want="$(jq -r .want <<<"$case")"
  bash "$here/../$hook.sh" <<<"$case" >/dev/null 2>&1
  got=$?
  if [ "$got" != "$want" ]; then
    failed=$((failed + 1))
    echo "FAIL [$hook] want $want, got $got: $(jq -r .tool_input.command <<<"$case" | head -1)"
  fi
done < "$here/cases.jsonl"
echo "$((n - failed))/$n cases pass"
# board.sh prints instead of blocking: its own cases, from a fixture.
bash "$here/board.sh" || failed=$((failed + 1))
# Not a hook: the skills' commands, as a session gets them.
bash "$here/skills.sh" || failed=$((failed + 1))
[ "$failed" -eq 0 ]
