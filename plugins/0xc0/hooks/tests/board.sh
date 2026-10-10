#!/usr/bin/env bash
# board.sh from a fixture, never gh: what a repo's session, the workspace's
# and one outside the org each get. Run by run.sh. Plain bash 3: no
# associative arrays, so it runs on a stock macOS too.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
n=0; failed=0

session() {  # session <name> <origin url>: a git dir whose origin is <url>, and board.sh's output for it
  git init -q "$tmp/$1" && git -C "$tmp/$1" remote add origin "$2"
  CLAUDE_PROJECT_DIR="$tmp/$1" BOARD_FIXTURE="$here/board-fixture.json" bash "$here/../board.sh" > "$tmp/$1.out"
}
fail() { failed=$((failed + 1)); echo "FAIL [board/$1] $2"; }
has() {  # has <session> <description> <line>
  n=$((n + 1)); grep -qxF -- "$3" "$tmp/$1.out" || grep -qF -- "$3" "$tmp/$1.out" || fail "$1" "$2: missing '$3'"
}
lacks() {
  n=$((n + 1)); ! grep -qF -- "$3" "$tmp/$1.out" || fail "$1" "$2: found '$3'"
}
in_order() {  # in_order <session> <description> <line>...: whole lines, one right after another
  local s="$1" d="$2" prev="" l; shift 2; n=$((n + 1))
  for line in "$@"; do
    l="$(grep -nxF -- "$line" "$tmp/$s.out" | head -1 | cut -d: -f1)"
    [ -n "$l" ] || { fail "$s" "$d: missing '$line'"; return; }
    [ -z "$prev" ] || [ "$l" -eq $((prev + 1)) ] || { fail "$s" "$d: '$line' not right after the line before"; return; }
    prev="$l"
  done
}

session vault https://github.com/0xc0-labs/vault.git
session workspace git@github.com:0xc0-labs/workspace.git
session other https://github.com/someone/else.git

has vault "names its repo" "## 0xc0-labs project board — 0xc0-labs/vault"
in_order vault "Ready by priority, then number" "Ready, by priority:" \
  "  - vault#12 P1 fix: twelve" "  - vault#10 P2 feat: ten" "  - vault#11 -- chore: eleven" "In Progress:"
in_order vault "its In Progress" "In Progress:" "  - vault#9 P1 feat: nine" "Blocked:"
in_order vault "its Blocked" "Blocked:" "  - vault#5 -- fix: five"
has vault "Todo counted, no status as Todo" "Todo, not ready to take: 2"
has vault "other repos counted" "Other repos: 2 open items, not this session's."
has vault "points at work-issue" "/0xc0:work-issue"
lacks vault "another repo's issue" "gitops#20"
lacks vault "a Done issue" "vault#6"

has workspace "the orchestrator's" "This is the orchestrator's session"
has workspace "the whole board" "  - gitops#20 P1 feat: twenty"
has workspace "with priorities" "  - vault#12 P1 fix: twelve"
lacks workspace "a Done issue" "vault#6"

has other "outside the org gets the whole board" "  - gitops#20 P1 feat: twenty"

rm -rf "$tmp"
echo "$((n - failed))/$n board cases pass"
[ "$failed" -eq 0 ]
