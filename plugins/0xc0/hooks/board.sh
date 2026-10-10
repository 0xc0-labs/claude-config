#!/usr/bin/env bash
# SessionStart: puts the open items of the org project board into the session,
# so no work starts without knowing what is tracked. Never blocks a session.
#
# In the workspace, the orchestrator's session, the whole board. In a repo's
# own session, that repo's Ready, In Progress and Blocked issues, Ready by
# priority, and only counts for the rest: the session works that repo alone.
#
# Every session runs on the operator's token, so they share GitHub's limits:
# the board is read once for all of them, into a cache on this machine that
# is reused for 120 seconds. Sessions starting together wait for the one that
# holds the lock instead of reading it again. When a read fails, the last
# board stands, with a note; when GitHub rate-limits it, no session asks again
# for 5 minutes, since every request during the penalty extends it.
#
# The tests (tests/board.sh) put a stand-in gh first on the PATH.
set -uo pipefail

ttl=120       # seconds a read is reused
pause=300     # seconds without a read after a rate limit
patience=30   # seconds a session waits for the one reading
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/0xc0"
cache="$cache_dir/board.json"
lock="$cache_dir/board.lock"
limited="$cache_dir/board.rate-limited"

dir="${CLAUDE_PROJECT_DIR:-$PWD}"
origin="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
repo=""
case "$origin" in
  *0xc0-labs/*) repo="$(sed -E 's#.*0xc0-labs/##; s#\.git$##; s#/$##' <<<"$origin")" ;;
esac
[ "$repo" = workspace ] && repo=""

command -v jq >/dev/null 2>&1 || { echo "0xc0: jq not found, project board not loaded."; exit 0; }

age() {  # age <path>: seconds since it was last written
  local m
  m="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)" || return 1
  echo $(( $(date +%s) - m ))
}
fresh() { [ -f "$cache" ] && [ "$(age "$cache")" -lt "$ttl" ]; }
paused() { [ -f "$limited" ] && [ "$(age "$limited")" -lt "$pause" ]; }
limit_note() { echo "rate-limited, no new read for $(( (pause - $(age "$limited") + 59) / 60 )) min"; }

read_board() {  # one read into the cache; on failure, why, on stdout
  local tmp err
  paused && { limit_note; return 1; }
  command -v gh >/dev/null 2>&1 || { echo "gh not found"; return 1; }
  tmp="$(mktemp "$cache_dir/board.XXXXXX")" || { echo "cannot write $cache_dir"; return 1; }
  if err="$(gh project item-list 1 --owner 0xc0-labs --limit 500 --format json 2>&1 >"$tmp")" \
    && jq -e '.items | type == "array"' "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$cache"
    return 0
  fi
  rm -f "$tmp"
  case "$err" in
    *"rate limit"*|*"too quickly"*) touch "$limited"; limit_note ;;
    *) echo "gh auth?" ;;
  esac
  return 1
}

why=""
if ! fresh; then
  mkdir -p "$cache_dir" 2>/dev/null
  # A lock left by a session that died is taken over after a minute.
  if [ -d "$lock" ] && [ "$(age "$lock" || echo 0)" -ge 60 ]; then
    mv "$lock" "$lock.$$" 2>/dev/null && rm -rf "$lock.$$"
  fi
  if mkdir "$lock" 2>/dev/null; then
    trap 'rmdir "$lock" 2>/dev/null' EXIT
    fresh || why="$(read_board)"
    rmdir "$lock" 2>/dev/null
    trap - EXIT
  else
    waited=0
    while [ -d "$lock" ] && [ "$waited" -lt $((patience * 2)) ]; do
      sleep 0.5; waited=$((waited + 1))
    done
    if ! fresh; then
      if paused; then why="$(limit_note)"; else why="gh auth?"; fi
    fi
  fi
fi

note=""
if [ -n "$why" ]; then
  [ -f "$cache" ] || { echo "0xc0: could not read the project board ($why)."; exit 0; }
  note="0xc0: this board is $(( $(age "$cache") / 60 )) min old: a new read failed ($why)."
fi
items="$(cat "$cache")"

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
${note:+
$note
}
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
${note:+
$note
}
$board
EOF
exit 0
