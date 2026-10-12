#!/usr/bin/env bash
# SessionStart. What it loads, and why it shares one cache: the README, Hooks.
set -uo pipefail

if [ "${OXC0_AUTOPILOT:-}" = 1 ]; then
  echo "0xc0: started by the autopilot: the issue is the contract, no board read."
  exit 0
fi

cache_ttl_seconds=120
rate_limit_pause_seconds=300
lock_wait_seconds=30
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

age() {
  local m now
  m="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)" || return 1
  now="$(date +%s)"
  echo $((now - m))
}
fresh() { [ -f "$cache" ] && [ "$(age "$cache")" -lt "$cache_ttl_seconds" ]; }
paused() { [ -f "$limited" ] && [ "$(age "$limited")" -lt "$rate_limit_pause_seconds" ]; }
limit_note() {
  local elapsed
  elapsed="$(age "$limited")"
  echo "rate-limited, no new read for $(( (rate_limit_pause_seconds - elapsed + 59) / 60 )) min"
}

read_board() {  # prints why it failed, and nothing on success
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
    while [ -d "$lock" ] && [ "$waited" -lt $((lock_wait_seconds * 2)) ]; do
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
  cache_age="$(age "$cache")"
  note="0xc0: this board is $((cache_age / 60)) min old: a new read failed ($why)."
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
