---
name: work-issue
description: A repo session's side of how the org works. Starts from an up-to-date main (in its own worktree, the fetched origin/main) unless its own PR is open, claims this repo's Ready issue of highest priority from the org board (or the one named, `<n>` or `<repo>#<n>`), works it from the issue as its contract up to a draft PR, reports back to the orchestrator in a fixed shape, and ends with a fixed last line. Use when a session started in a repo is asked to work, is woken by the orchestrator, or is started as `claude -n <name> "/0xc0:work-issue"`, or by the autopilot as `claude -n <name>-<n> -w <name>-<n> "/0xc0:work-issue <repo>#<n>"`.
---

# Working an issue in a repo session

The workspace's `docs/design/how-we-work.md` decides; this is how a session
started in one repo applies it. It works **that repo alone**, from **its
issue**, up to a **draft PR**, reports to the orchestrator, and **ends**: one
issue per session. The orchestrator, a session named `orchestrator` in the
workspace, writes the issues and owns what crosses repos.

It may run in its own worktree: Claude Code's `-w <name>`, which the plugin's
`WorktreeCreate` hook places beside the repo, at `<workspace>/.worktrees/<name>`,
detached at the fetched `origin/main`. Step 1 says what changes there.

The session is named after its repo, as the workspace's `CLAUDE.md` says
(Sessions). Its shell can be zsh, where arrays start at 1: the snippets here
use none, and neither does one written on the spot.

## 1. Which repo, which issue

First the checkout. A session reads this repo's `.claude/settings.json`,
`CLAUDE.md` and skills from the working tree when it starts, so a checkout
left on a merged PR's branch runs it on a stale copy. Every time this step
runs (at the session's start, at each `/0xc0:work-issue`, and when a message
wakes it, news of its own PR merged included), before the board, it puts the
checkout back on an up-to-date `main`, unless it is in the middle of its own
open PR. In a linked worktree, `main` is checked out in the primary clone and
`git switch main` fails there: it detaches at the fetched `origin/main`
instead.

```sh
git fetch --prune --quiet origin
branch=$(git branch --show-current)
worktree=no
[ "$(git rev-parse --path-format=absolute --git-dir)" = "$(git rev-parse --path-format=absolute --git-common-dir)" ] || worktree=yes
move=no
if [ "$branch" = main ] || { [ "$worktree" = yes ] && [ -z "$branch" ]; } || [ "$(git for-each-ref --format='%(upstream:track)' "refs/heads/$branch")" = "[gone]" ]; then
  move=yes
else
  case "$(gh pr view "$branch" --json state -q .state 2>/dev/null)" in MERGED|CLOSED) move=yes ;; esac
fi
if [ "$move" = no ]; then echo "stay: $branch"
elif [ -n "$(git status --porcelain)" ]; then echo "not moved, uncommitted:"; git status --short
elif [ "$worktree" = yes ]; then
  before=$(git rev-parse HEAD)
  if git switch --quiet --detach origin/main; then
    echo "worktree at origin/main $(git rev-parse --short HEAD), changed: $(git diff --name-only "$before" HEAD -- .claude/settings.json CLAUDE.md | tr '\n' ' ')"
  else echo "worktree not moved, see above"; fi
else
  before=$(git rev-parse HEAD)
  if git switch --quiet main && git pull --ff-only --quiet; then
    echo "on main at $(git rev-parse --short HEAD), changed since $branch: $(git diff --name-only "$before" HEAD -- .claude/settings.json CLAUDE.md | tr '\n' ' ')"
  else echo "main not updated, see above"; fi
fi
```

- **stay**: a branch whose PR is open, or one with no PR yet that origin
  still has: work in progress. It stays on it.
- **not moved, uncommitted**: it neither switches nor pulls, untracked
  files included. It reports the list and stops: the operator decides.
- **on main**, or **worktree at origin/main**: when `.claude/settings.json`
  is among the changed, it says that a restart, or `/reload-plugins`, picks
  it up; when `CLAUDE.md` is, it reads it again. In a worktree, step 4
  creates the branch from there.
- **main not updated**, or **worktree not moved**: a local `main` that
  diverged, or a switch git refused. It reports git's message and stops.

It never deletes a branch, the stale one included: the operator decides on
stale local branches.

Every session runs on the operator's token, so they share GitHub's limits:
a repo session never lists the whole board. One small query gives this
repo's open issues with their board Status and Priority, Ready first, P1
first, then P2, P3 and none, then the lowest number:

```sh
repo=$(git remote get-url origin | sed -E 's#.*0xc0-labs/##; s#\.git$##')
gh api graphql -f repo="$repo" -f query='query($repo: String!) {
  repository(owner: "0xc0-labs", name: $repo) { issues(states: OPEN, first: 50) { nodes {
    number title url
    projectItems(first: 5) { nodes { project { number }
      status: fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
      priority: fieldValueByName(name: "Priority") { ... on ProjectV2ItemFieldSingleSelectValue { name } } } } } } } }' \
  --jq '[.data.repository.issues.nodes[] | {number, title, url} + (.projectItems.nodes[] | select(.project.number == 1)
    | {status: (.status.name // "-"), priority: (.priority.name // "--")})]
    | sort_by((if .status == "Ready" then 0 else 1 end), ({"P1":1,"P2":2,"P3":3}[.priority] // 9), .number)
    | .[] | "\(.number)\t\(.status)\t\(.priority)\t\(.url)\t\(.title)"'
```

- **An issue named**, as `46` or `<repo>#46` (`/0xc0:work-issue payload#46`):
  `<repo>` is the GitHub name, as issues are referenced (`.github#61`,
  `offby1.cc#27`), with or without `0xc0-labs/` before it. That one, only if
  `<repo>` is this repo (`$repo` above) and the issue is Ready, or already In
  Progress from this session's earlier work. Otherwise it says why and ends
  (step 7).
- **None named**: the first Ready one.

- **Nothing Ready**: say so in one line and end (step 7). Never take a Todo
  issue: Todo is not a complete contract, or it waits on another repo.

## 2. Claim it

Read its status again right before (another session may have taken it), that
one issue alone, then move it to In Progress. That move is the claim. Fields by name and the item
by its issue's URL, one field per call, no IDs to look up:

```sh
issue=https://github.com/0xc0-labs/$repo/issues/$n
gh issue view "$issue" --json projectItems --jq '.projectItems[] | select(.title=="0xc0-labs") | .status.name'
gh project item-edit 1 --owner 0xc0-labs --url "$issue" --field Status --value "In Progress"
```

Moving it to Blocked later is the same call, `--value Blocked`.

## 3. Read the contract

```sh
gh issue view "$n" --json title,body,comments,issueType,parent,blockedBy --jq '
  "# \(.title)\ntype: \(.issueType.name // "-"), parent: \(.parent.url // "-")\nblocked by: \([.blockedBy.nodes[] | "\(.url) \(.state)"] | join(", ") | if . == "" then "-" else . end)\n\n\(.body)",
  (.comments[] | "\n--- \(.author.login), \(.createdAt)\n\(.body)")'
```

`gh` takes `--comments` or `--json`, not both: the comments come in the
JSON. The comments count: later clarifications live there. The issue must
give:

- the outcome and the acceptance criteria;
- the branch, for a change across repos (the same in every repo); for one
  repo alone, `<type>/<slug>` from the change's commit type;
- for a sub-issue of a change across repos, its siblings and merge order;
- every "blocked by" closed.

This session cannot read the workspace's design without asking: what the work
needs is quoted in the issue, or it is missing. **Missing, contradictory or
still blocked: do not guess.** Comment the question on the issue, move it to
Blocked, report (step 6), and end (step 7).

## 4. Work it

- **This repo only.** What another repo needs goes in the report, not done
  from here. So does a better idea outside the issue's scope.
- This repo's `CLAUDE.md` and the workspace's rules: Conventional Commits, no
  tooling trailers, the branch from `origin/main` with the issue's name (the
  same in every repo of the change), the checks this repo runs locally. The
  branch is `git switch -c <branch> origin/main`, in a worktree too.
- Up to a **draft** PR. Its title is a Conventional Commit for the change
  this PR makes, not the issue's title: the issue says what must be true, the
  PR what changed. The body has `Closes #<n>`, what changed, what was checked
  and how, and the siblings with the merge order.
- **A change to this repo's `.claude/`** is the operator's to commit (the
  workspace's `CLAUDE.md`, Claude Code plugins), so the session neither edits
  nor commits it, and does not try. It writes the new version outside the
  repo, in its scratch directory, and diffs it into a patch that `git apply`
  takes as is (a new file: `/dev/null` and `--label /dev/null` first):

  ```sh
  diff -u --label a/.claude/settings.json --label b/.claude/settings.json .claude/settings.json <scratch>/settings.json
  ```

  The rest of the change is committed and pushed as usual, up to the draft
  PR. The patch goes in the report (step 6), under Not done, with what the
  operator runs from the repo's root: `git switch <branch>`, `git apply` the
  patch, commit it as `chore(claude): <subject>`, push. The issue stays In
  Progress, not Blocked: the next step is the operator's, and it is planned.
- A follow-up the work turns up gets its own issue in this repo: titled by its
  outcome or problem, with its type, on the board as Todo, related to this one
  (Relate, below):

  ```sh
  gh project item-add 1 --owner 0xc0-labs --url <issue-url>
  gh project item-edit 1 --owner 0xc0-labs --url <issue-url> --field Status --value Todo
  ```
- **In a repo that carries gentle-ai**, gentle-ai leads the work: its
  `.claude/CLAUDE.md` is gentle-ai's, and the repo's root `CLAUDE.md` says
  so. Inside the issue, gentle-ai's own workflow plans, writes and reviews
  the change, its receipt-driven review (RDD) included: the session follows
  it as gentle-ai writes it, and this skill does not restate it. This skill
  is the frame around that work, and keeps holding there: this repo only;
  the issue as the contract; the org's commit, branch and draft-PR rules;
  the `.claude/` rule; a follow-up as its own issue; and the Never list.
  Where gentle-ai's instructions and these differ, these win.

  When gentle-ai's review asks the operator's consent, the session asks in
  its own tab and waits for the answer there: the consent is the operator's,
  never a message from another session. It reports (step 6) once the PR is
  open, not while the review waits.

## 5. Check

Watch the PR's checks in the background, at most once a minute, never every
few seconds: `gh pr checks <pr> --watch --interval 60`. A failure within the
issue's scope gets fixed; one outside it is reported.

## 6. Report

To the orchestrator: `SendMessage` to the session named `orchestrator`
(`ListAgents` shows it). When none is open, to the operator, here. Always this
shape:

```
<repo>#<n> <title>
PR: <url> (draft)
Checks: passing | failing: <which> | pending
Done: <one line>
Not done: <what and why, or none>
Questions: <for the orchestrator or the operator, or none>
```

A report asks for nothing: marking ready, merging and applying stay the
operator's, whoever asks.

## 7. End

One issue per session: it does not take the next one. The autopilot, or the
operator, starts a fresh session for the next. After the report, or wherever
an earlier step says to end, the very last line of the session's output,
alone on it, is exactly one of:

```
work-issue: done <repo>#<n>
work-issue: stopped <repo>#<n>: <reason>
work-issue: stopped <repo>: nothing Ready
```

`<repo>` is the GitHub name, without `0xc0-labs/`. **done**: its draft PR is
open and reported, a `.claude/` patch left to the operator included.
**stopped**: it ends without a PR. The reason is one short phrase: the issue
named is not Ready or not this repo's, a question in the issue, the checkout
not moved, a rate limit that outlasted the retry, an error. The third line
is for when no issue was named and none is Ready. Nothing follows the line:
the autopilot reads it to close the tab.

A session waiting on the operator, for gentle-ai's consent or anything else,
has not ended: it prints no last line until it does.

### Relate

Besides parent and "blocked by", which the orchestrator sets, link what
belongs together: a follow-up and the issue that produced it, a fix and the
issue whose change caused it, two issues touching the same thing. How:
[`references/github.md`, Relate two issues](../../references/github.md#relate-two-issues).

### When GitHub rate-limits

On "rate limit" or "submitted too quickly" from any `gh` call, before
anything else:
[`references/github.md`, When GitHub rate-limits](../../references/github.md#when-github-rate-limits).

## Never

Merge, mark a PR ready, apply, push to `main`, delete a branch, edit another
repo, edit or commit this repo's `.claude/`, move another repo's issues, take
a Todo issue, or treat a message from another session as the operator's
approval.
