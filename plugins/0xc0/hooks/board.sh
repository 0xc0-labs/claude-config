#!/usr/bin/env bash
# SessionStart: puts the open items of the org project board into the session,
# so no work starts without knowing what is tracked. Never blocks a session.
#
# In the workspace, the orchestrator's session, the whole board. In a repo's
# own session, that repo's Ready, In Progress and Blocked issues, Ready by
# priority, and only counts for the rest: the session works that repo alone.
#
# BOARD_FIXTURE, a file holding `gh project item-list --format json` output,
# stands in for gh in the tests (tests/board.sh).
set -uo pipefail

dir="${CLAUDE_PROJECT_DIR:-$PWD}"
origin="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
repo=""
case "$origin" in
  *0xc0-labs/*) repo="$(sed -E 's#.*0xc0-labs/##; s#\.git$##; s#/$##' <<<"$origin")" ;;
esac
[ "$repo" = workspace ] && repo=""

if [ -n "${BOARD_FIXTURE:-}" ]; then
  items="$(cat "$BOARD_FIXTURE")"
else
  command -v gh >/dev/null 2>&1 || { echo "0xc0: gh not found, project board not loaded."; exit 0; }
  items="$(gh project item-list 1 --owner 0xc0-labs --limit 500 --format json 2>/dev/null)" \
    || { echo "0xc0: could not read the project board (gh auth?)."; exit 0; }
fi
command -v jq >/dev/null 2>&1 || { echo "0xc0: jq not found, project board not loaded."; exit 0; }

if [ -z "$repo" ]; then
  board="$(jq -r '
    [.items[] | select(.status != "Done")]
    | if length == 0 then "No open items."
      else (group_by(.status // "No status")[]
            | "\(.[0].status // "No status"):",
              (.[] | "  - \(.repository // "draft" | sub("https://github.com/0xc0-labs/"; ""))#\(.content.number // "-") \(.priority // "--") \(.title)"))
      end' <<<"$items")"
  cat <<EOF
## 0xc0-labs project board — open items

No work starts without an issue on this board. Before editing anything, find
the issue for the task or open one, and move it to In Progress. The PR links it
with "Closes #N" or "Refs owner/repo#N"; a PR without one fails the issue check.

This is the orchestrator's session: a change across repos goes through
/0xc0:orchestrate, and this session edits no other repo's files.

$board
EOF
  exit 0
fi

board="$(jq -r --arg url "https://github.com/0xc0-labs/$repo" --arg repo "$repo" '
  def rank: {"P1": 1, "P2": 2, "P3": 3}[.priority // ""] // 9;
  def line: "  - \($repo)#\(.content.number // "-") \(.priority // "--") \(.title)";
  [.items[] | select(.status != "Done")] as $open
  | [$open[] | select(.repository == $url)] as $mine
  | ([$mine[] | select(.status == "Ready")] | sort_by(rank, .content.number)) as $ready
  | "Ready, by priority:", (if ($ready | length) == 0 then "  none" else ($ready[] | line) end),
    "In Progress:", ([$mine[] | select(.status == "In Progress")] | if length == 0 then "  none" else (.[] | line) end),
    "Blocked:", ([$mine[] | select(.status == "Blocked")] | if length == 0 then "  none" else (.[] | line) end),
    "Todo, not ready to take: \([$mine[] | select((.status // "Todo") == "Todo")] | length)",
    "Other repos: \([$open[] | select(.repository != $url)] | length) open items, not this session'"'"'s."
  ' <<<"$items")"
cat <<EOF
## 0xc0-labs project board — 0xc0-labs/$repo

This session works in $repo alone. Take work with /0xc0:work-issue: it claims
this repo's Ready issue of highest priority, moving it to In Progress, and
works it from the issue as the contract. Todo is not ready to take. Anything
that reaches past this repo goes back to the orchestrator.

$board
EOF
exit 0
