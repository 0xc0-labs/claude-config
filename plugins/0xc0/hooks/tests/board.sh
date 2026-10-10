#!/usr/bin/env bash
# board.sh against a stand-in gh, never the real one: what a repo's session,
# the workspace's and one outside the org each get, and the board's cache:
# fresh, stale, a failed read, a rate limit, sessions starting together, a
# lock left behind. Run by run.sh. Plain bash 3: no associative arrays, so it
# runs on a stock macOS too.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
n=0; failed=0
fixture="$here/board-fixture.json"

# The stand-in gh: logs the call next to its cache, waits GH_DELAY seconds,
# then fails with GH_ERROR or prints the fixture.
mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$XDG_CACHE_HOME/gh.log"
sleep "${GH_DELAY:-0}"
[ -z "${GH_ERROR:-}" ] || { echo "$GH_ERROR" >&2; exit 1; }
cat "$BOARD_FIXTURE"
EOF
chmod +x "$tmp/bin/gh"

session() {  # session <name> <origin url> <cache>: board.sh's output for a git dir whose origin is <url>
  git init -q "$tmp/$1" && git -C "$tmp/$1" remote add origin "$2"
  mkdir -p "$tmp/$3"
  PATH="$tmp/bin:$PATH" XDG_CACHE_HOME="$tmp/$3" CLAUDE_PROJECT_DIR="$tmp/$1" BOARD_FIXTURE="$fixture" \
    GH_ERROR="${GH_ERROR:-}" GH_DELAY="${GH_DELAY:-0}" bash "$here/../board.sh" > "$tmp/$1.out"
}
seed() {  # seed <cache> <minutes old>: a cached board, its vault#12 retitled "fix: twelve, cached"
  mkdir -p "$tmp/$1/0xc0"
  jq '(.items[] | select(.content.number == 12) | .title) = "fix: twelve, cached"' "$fixture" > "$tmp/$1/0xc0/board.json"
  aged "$tmp/$1/0xc0/board.json" "$2"
}
aged() { perl -e '$t = time - 60 * shift; utime $t, $t, @ARGV' "$2" "$1"; }  # aged <path> <minutes>
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
reads() {  # reads <cache> <description> <n>: gh was called n times for that cache
  local got=0; n=$((n + 1))
  [ -f "$tmp/$1/gh.log" ] && got="$(wc -l < "$tmp/$1/gh.log" | tr -d ' ')"
  [ "$got" = "$3" ] || fail "$1" "$2: gh read the board $got times, want $3"
}

vault=https://github.com/0xc0-labs/vault.git
twelve="  - vault#12 P1 fix: twelve"

# What each session gets, the three sharing one cache.
session vault "$vault" cache
session workspace git@github.com:0xc0-labs/workspace.git cache
session other https://github.com/someone/else.git cache

has vault "names its repo" "## 0xc0-labs project board — 0xc0-labs/vault"
in_order vault "Ready by priority, then number" "Ready, by priority:" \
  "$twelve" "  - vault#10 P2 feat: ten" "  - vault#11 -- chore: eleven" "In Progress:"
in_order vault "its In Progress" "In Progress:" "  - vault#9 P1 feat: nine" "Blocked:"
in_order vault "its Blocked" "Blocked:" "  - vault#5 -- fix: five"
has vault "Todo counted, no status as Todo" "Todo, not ready to take: 2"
has vault "other repos counted" "Other repos: 2 open items, not this session's."
has vault "points at work-issue" "/0xc0:work-issue"
lacks vault "another repo's issue" "gitops#20"
lacks vault "a Done issue" "vault#6"
lacks vault "no note on a fresh read" "0xc0: "

has workspace "the orchestrator's" "This is the orchestrator's session"
has workspace "the whole board" "  - gitops#20 P1 feat: twenty"
has workspace "with priorities" "$twelve"
lacks workspace "a Done issue" "vault#6"

has other "outside the org gets the whole board" "  - gitops#20 P1 feat: twenty"
reads cache "three sessions, one read" 1

# A fresh cache is used as it is: gh is not called, even when it would fail.
seed fresh 1
GH_ERROR="should not be called" session fresh "$vault" fresh
has fresh "the cached board" "  - vault#12 P1 fix: twelve, cached"
lacks fresh "no note" "0xc0: "
reads fresh "a fresh cache, no read" 0

# A stale cache is read again, and the new board replaces it.
seed stale 10
session stale "$vault" stale
has stale "the new board" "$twelve"
lacks stale "not the old one" "fix: twelve, cached"
lacks stale "no note" "0xc0: "
reads stale "a stale cache, one read" 1
n=$((n + 1)); cmp -s "$fixture" "$tmp/stale/0xc0/board.json" || fail stale "the cache holds the new board"

# A failed read falls back to the stale cache, with a note; with no cache, to the one line.
seed failed 10
GH_ERROR="HTTP 401: Bad credentials (https://api.github.com/graphql)" session failed "$vault" failed
has failed "the note" "0xc0: this board is 10 min old: a new read failed (gh auth?)."
has failed "the cached board" "  - vault#12 P1 fix: twelve, cached"
GH_ERROR="HTTP 401: Bad credentials (https://api.github.com/graphql)" session none "$vault" none
has none "the could-not-read line" "0xc0: could not read the project board (gh auth?)."
lacks none "no board" "Ready, by priority:"

# A rate limit: the stale board with a note, and no session asks again for 5 minutes.
seed limited 10
GH_ERROR="GraphQL: API rate limit exceeded for user ID 1." session limited "$vault" limited
has limited "the note" "0xc0: this board is 10 min old: a new read failed (rate-limited, no new read for 5 min)."
has limited "the cached board" "  - vault#12 P1 fix: twelve, cached"
session limited-next "$vault" limited
has limited-next "still the note" "a new read failed (rate-limited, no new read for 5 min)."
reads limited "no read during the pause" 1
aged "$tmp/limited/0xc0/board.rate-limited" 6
session limited-after "$vault" limited
has limited-after "read again after the pause" "$twelve"
reads limited "one more read after it" 2

# Sessions starting together: one reads, the others wait for its cache.
for s in 1 2 3 4 5; do GH_DELAY=2 session "burst$s" "$vault" burst & done
wait
reads burst "five sessions together, one read" 1
for s in 1 2 3 4 5; do has "burst$s" "the board for each" "$twelve"; done

# A lock left by a session that died is taken over after a minute.
mkdir -p "$tmp/dead/0xc0/board.lock"
aged "$tmp/dead/0xc0/board.lock" 2
session dead "$vault" dead
has dead "the board" "$twelve"
reads dead "one read" 1

rm -rf "$tmp"
echo "$((n - failed))/$n board cases pass"
[ "$failed" -eq 0 ]
