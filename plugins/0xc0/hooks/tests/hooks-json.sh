#!/usr/bin/env bash
# Every hooks.json command run through a shell, as Claude Code runs it, from a
# plugin path with a space: a hook that cannot start lets the call through (#51).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
n=0; failed=0
fail() { failed=$((failed + 1)); echo "FAIL [hooks.json] $1"; }
export CLAUDE_PLUGIN_ROOT="$tmp/plugin root"
cp -R "$here/../.." "$CLAUDE_PLUGIN_ROOT"

run() {  # run <hooks.json command> <tool call's command>
  jq -n --arg c "$2" --arg f "$tmp/notes.md" '{tool_input: {command: $c, file_path: $f}}' \
    | OXC0_AUTOPILOT=1 sh -c "$1" >/dev/null 2>&1
}

while IFS= read -r cmd; do
  n=$((n + 1))
  run "$cmd" true; got=$?
  [ "$got" -eq 0 ] || fail "'$cmd' exits $got on a harmless call, want 0"
  case "$cmd" in
    */no-apply.sh*)
      n=$((n + 1))
      run "$cmd" "tofu apply"; got=$?
      [ "$got" -eq 2 ] || fail "'$cmd' exits $got on tofu apply, want 2" ;;
  esac
done < <(jq -r '.hooks[][].hooks[].command' "$here/../hooks.json")

echo "$((n - failed))/$n hooks.json cases pass"
[ "$failed" -eq 0 ]
