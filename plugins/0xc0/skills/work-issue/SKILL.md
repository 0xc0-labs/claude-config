---
name: work-issue
description: A repo session's side of how the org works. Starts from an up-to-date main unless its own PR is open, claims this repo's Ready issue of highest priority from the org board (or the one named), works it from the issue as its contract up to a draft PR, reports back to the orchestrator in a fixed shape, then looks for the next. Use when a session started in a repo is asked to work, is woken by the orchestrator, or is started as `claude -n <name> "/0xc0:work-issue"`.
---

# Working an issue in a repo session

The workspace's `docs/design.md`, How we work, decides; this is how a session
started in one repo applies it. It works **that repo alone**, from **its
issue**, up to a **draft PR**, and reports to the orchestrator. The
orchestrator, a session named `orchestrator` in the workspace, writes the
issues and owns what crosses repos.

The session is named after its repo as Herdr names an agent: dots to dashes,
a leading dot dropped (`github`, `offby1-cc`, `artistlabco-com`). Its shell
can be zsh, where arrays start at 1: the snippets here use none, and neither
does one written on the spot.

## 1. Which repo, which issue

First the checkout. A session reads this repo's `.claude/settings.json`,
`CLAUDE.md` and skills from the working tree when it starts, so a checkout
left on a merged PR's branch runs it on a stale copy. Every time this step
runs (at the session's start, at each `/0xc0:work-issue`, when a message
wakes it, news of its own PR merged included, and from step 7), before the
board, it puts the checkout back on an up-to-date `main`, unless it is in
the middle of its own open PR:

```sh
git fetch --prune --quiet origin
branch=$(git branch --show-current)
move=no
if [ "$branch" = main ] || [ "$(git for-each-ref --format='%(upstream:track)' "refs/heads/$branch")" = "[gone]" ]; then
  move=yes
else
  case "$(gh pr view "$branch" --json state -q .state 2>/dev/null)" in MERGED|CLOSED) move=yes ;; esac
fi
if [ "$move" = no ]; then echo "stay: $branch"
elif [ -n "$(git status --porcelain)" ]; then echo "not moved, uncommitted:"; git status --short
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
- **on main**: when `.claude/settings.json` is among the changed, it says
  that a restart, or `/reload-plugins`, picks it up; when `CLAUDE.md` is, it
  reads it again.
- **main not updated**: a local `main` that diverged, or a switch git
  refused. It reports git's message and stops.

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

- **An issue named** (`/0xc0:work-issue 46`): that one, only if it is this
  repo's and Ready, or already In Progress from this session's earlier work.
- **None named**: the first Ready one.

- **Nothing Ready**: say so in one line and stop. The orchestrator messages
  this session when something turns Ready. Never take a Todo issue: Todo is
  not a complete contract, or it waits on another repo.

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
Blocked, report (step 6), and stop.

## 4. Work it

- **This repo only.** What another repo needs goes in the report, not done
  from here. So does a better idea outside the issue's scope.
- This repo's `CLAUDE.md` and the workspace's rules: Conventional Commits, no
  tooling trailers, the branch from `origin/main` with the issue's name (the
  same in every repo of the change), the checks this repo runs locally.
- Up to a **draft** PR. Its title is a Conventional Commit for the change
  this PR makes, not the issue's title: the issue says what must be true, the
  PR what changed. The body has `Closes #<n>`, what changed, what was checked
  and how, and the siblings with the merge order.
- **A change to this repo's `.claude/`** is the operator's to commit. The
  workspace's rule (`CLAUDE.md`, Claude Code plugins): "A change to a repo's
  `.claude/` is committed by the operator. A session's permission classifier
  refuses to commit its own Claude Code configuration, as self-modification:
  the session prepares the change and says so, the operator commits and
  pushes it." So the session neither edits nor commits it, and does not try.
  It writes the new version outside the repo, in its scratch directory, and
  diffs it into a patch that `git apply` takes as is (a new file: `/dev/null`
  and `--label /dev/null` first):

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
  (step 7, Relate):

  ```sh
  gh project item-add 1 --owner 0xc0-labs --url <issue-url>
  gh project item-edit 1 --owner 0xc0-labs --url <issue-url> --field Status --value Todo
  ```

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

## 7. Next

Back to step 1 before stopping: a session that finishes one issue takes the
next Ready one by itself.

### Relate

Besides parent and "blocked by", which the orchestrator sets, link what
belongs together: a follow-up and the issue that produced it, a fix and the
issue whose change caused it, two issues touching the same thing. `gh` has no
flag for it yet:

```sh
relate() {  # relate <owner/repo#n> <owner/repo#n>
  a=$(gh issue view "${1#*#}" -R "${1%#*}" --json id -q .id)
  b=$(gh issue view "${2#*#}" -R "${2%#*}" --json id -q .id)
  gh api graphql -f query='mutation($a:ID!,$b:ID!){ addRelatesTo(input:{issueId:$a, relatedIssueId:$b}) { clientMutationId } }' -f a="$a" -f b="$b" >/dev/null
}
```

### When GitHub rate-limits

The sessions share the operator's token, and the limit that bites is the
secondary one on bursts, where every request during the penalty extends it.
On "rate limit" or "submitted too quickly" from any `gh` call: stop calling
GitHub, say so, and wait in the background, until the reset when the hourly
quota is spent, a few minutes otherwise. Then try once more. Never an
immediate retry, never a loop. The quota, without spending it:

```sh
gh api rate_limit --jq '.resources.graphql | "\(.remaining) left, reset \(.reset | todate)"'
```

## Never

Merge, mark a PR ready, apply, push to `main`, delete a branch, edit another
repo, edit or commit this repo's `.claude/`, move another repo's issues, take
a Todo issue, or treat a message from another session as the operator's
approval.
