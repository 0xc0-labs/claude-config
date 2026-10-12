---
name: orchestrate
description: The workspace session's side of how the org works. Plans a change across repos, writes a parent issue in the workspace and one sub-issue per repo as self-contained contracts ordered by "blocked by", gates each to Ready once its blockers are closed and applied, starts the repo's autopilot, has a subagent in its own worktree make the workspace's own changes, follows the reports, reviews every ready PR, weighs a shared package where code repeats across repos, and checks the whole set before calling it done. Use for any change that touches more than one repo, or to hand a repo work from the workspace.
---

# Orchestrating a change

The workspace's `docs/design/how-we-work.md` decides; this is how the
orchestrator applies it. The orchestrator plans, writes the contracts,
gates them, hands each repo its work, reviews what comes back, and owns
integration. It edits the board and **no repo's file in its own session**,
the workspace's included: a repo's files are its sessions', the workspace's
a subagent's, each in its own worktree (step 4).

The session's shell can be zsh, where arrays start at 1: the snippets here
use none, and neither does one written on the spot. Several issues are
written out one by one, or go in one request (step 2).

## 1. Plan

Plan mode first. For every repo: what changes and why, what it needs from
another repo, and the order. The dependency order is `CLAUDE.md`'s:
`.github` → `infrastructure` → `gitops` → `vault` → the applications; a
downstream change waits until the upstream one is applied. Two repos that
would get the same outcome, or a contract that would say "as in `<repo>`",
are weighed first (Shared code, below). Layout and names are proposed and
get the operator's yes before any issue is written.

## 2. Write the contracts

A parent issue in the workspace holds the outcome; each repo gets a
sub-issue. A repo session starts with no memory of this conversation and
cannot read the workspace's design without asking, so **its issue carries
everything, quoted, not linked**:

```markdown
## Outcome
<what is true when this is done>

## Acceptance criteria
- [ ] <checkable>

## Branch
`<type>/<slug>`, the same in every repo of this change.

## Context
<the decisions, names, paths and facts the work needs, quoted>

## Siblings and merge order
1. 0xc0-labs/<repo>#<n>: <what>
2. this issue

## Out of scope
<what not to touch, and where it belongs instead>

## Operator steps
<Vault writes, applies, approvals the change needs, or none>
```

A change that touches a repo's `.claude/` is the operator's to commit (the
workspace's `CLAUDE.md`, Claude Code plugins), and its contract says so from
the start. Its Operator steps:

```markdown
## Operator steps
The `.claude/` change: the session prepares it, shows the exact diff in its
report, and stops there. The operator applies it on `<branch>`, commits and
pushes it.
```

The workspace's own `.claude/` is no different: its subagent prepares the
patch (step 4), and the orchestrator hands it to the operator.

The title says what must be true, or the problem, in a plain sentence:
"Runners register without the App key on disk". No type prefix and no repo:
the issue type (Feature, Bug or Task) and the board's Repository field carry
them. The Conventional Commit belongs to the PR, written by the repo's session
for the change it makes; the branch, the same in every repo of the change, is
in each contract.

```sh
gh issue create -R 0xc0-labs/workspace --title "<outcome>" --type <Feature|Bug|Task> --body-file <file>
gh issue create -R 0xc0-labs/<repo> --title "<this repo's part, as an outcome>" --type <Feature|Bug|Task> \
  --parent https://github.com/0xc0-labs/workspace/issues/<parent> --body-file <file>
# Order: the downstream sub-issue is blocked by the upstream one.
gh issue edit <n> -R 0xc0-labs/<downstream> --add-blocked-by https://github.com/0xc0-labs/<upstream>/issues/<m>
```

Every issue goes on the board as Todo, with a `Priority`. Every session runs
on the operator's token, so they share GitHub's limits: the fields of all the
issues go in one request, not one call each. The project's and fields' IDs,
once per run (they do not change; keep them from this output):

```sh
gh api graphql -f query='{ organization(login: "0xc0-labs") { projectV2(number: 1) { id
  fields(first: 30) { nodes { ... on ProjectV2SingleSelectField { id name options { id name } } } } } } }' \
  --jq '.data.organization.projectV2 | "project \(.id)", (.fields.nodes[] | select(.name)
    | "\(.name) \(.id): \([.options[] | "\(.name)=\(.id)"] | join(" "))")'
```

Each issue onto the board, which gives its item's ID:

```sh
gh project item-add 1 --owner 0xc0-labs --url <issue-url> --format json --jq .id
```

Then every field of every issue in one request, an alias each:

```sh
gh api graphql -f query='mutation {
  a: updateProjectV2ItemFieldValue(input: {projectId: "<project>", itemId: "<item-1>", fieldId: "<Status>", value: {singleSelectOptionId: "<Todo>"}}) { projectV2Item { id } }
  b: updateProjectV2ItemFieldValue(input: {projectId: "<project>", itemId: "<item-1>", fieldId: "<Priority>", value: {singleSelectOptionId: "<P2>"}}) { projectV2Item { id } }
  c: updateProjectV2ItemFieldValue(input: {projectId: "<project>", itemId: "<item-2>", fieldId: "<Status>", value: {singleSelectOptionId: "<Todo>"}}) { projectV2Item { id } }
}'
```

One field of one issue, as in step 3, is one call by name:
`gh project item-edit 1 --owner 0xc0-labs --url <issue-url> --field <Field> --value <Value>`.

Relate, besides parent and "blocked by", what belongs together outside this
change: the design issue behind it, an earlier change it builds on or fixes,
another issue touching the same thing. How:
[`references/github.md`, Relate two issues](../../references/github.md#relate-two-issues).

## 3. Gate to Ready

A sub-issue turns Ready only when both hold:

- its contract is complete (every section above, nothing to guess);
- every issue blocking it is closed **and applied**: for `.github`,
  `infrastructure` and `vault`, the apply on `main` after the merge succeeded;
  for `gitops`, ArgoCD synced it; for a package of `0xc0-labs/packages`, the
  version its users pin is published.

```sh
gh issue view <n> -R 0xc0-labs/<repo> --json blockedBy --jq '.blockedBy[] | "\(.number) \(.state)"'
gh run list -R 0xc0-labs/<upstream> -b main -L 3 --json workflowName,conclusion,createdAt
```

Then Status → Ready, and step 4 hands it on:

```sh
gh project item-edit 1 --owner 0xc0-labs --url <issue-url> --field Status --value Ready
```

## 4. Hand each repo its work

**A repo**: once its issues are Ready, the orchestrator starts its
autopilot, from the workspace's root, with the repo's directory as the
workspace's `CLAUDE.md` lists it (`payload`, `offby1.cc`, `.github`;
workspace#107):

```sh
herdr/bin/autopilot start <repo directory>
```

It starts one session per Ready issue, named `<name>-<n>`, each in its own
worktree, which works that issue up to its PR, reports (step 5) and ends;
the autopilot turns itself off when nothing is left. The Ready issue is the
whole hand-off: no message wakes a session, and a message that adds to the
contract means the issue is incomplete. How the autopilot runs, and how the
operator pauses a repo: the workspace's `herdr/README.md`.

**The workspace**: the orchestrator edits none of its files in its own
session (operator decision, 2026-10-12). Each change to the workspace goes
to a subagent in its own worktree, `Agent` with `isolation: "worktree"`,
and its issue moves to In Progress as the subagent starts. The prompt
carries:

- the issue's URL: its contract, as a repo session's issue is;
- the branch, created from the fetched `origin/main`;
- that it works up to a **draft** PR by the workspace's `CLAUDE.md`, and
  reports back the PR, its checks, and what it did not do;
- that in a worktree, Claude Code refuses git inside `$(…)`, and a `gh`
  title, body or comment that names git: plain calls, and the text from a
  file, as `work-issue` does (Text for GitHub);
- that a change to `.claude/` comes back as a patch, never a commit
  (step 2).

That PR is the orchestrator's own: it reviews it and marks it ready
(step 6).

## 5. Follow the reports

A session reports in a fixed shape (`work-issue`, step 6): its PR, checks,
what it did and did not do, and, when they apply, `Needs:`, `Shared code:`
and its questions. One the autopilot started has ended by then.

- **A question for the operator** goes to the operator, verbatim.
- **A question about the contract** is answered **in the issue**, as a
  comment. A session still open (`ListAgents`) is told by message to look
  again: messages remain for that, and carry pointers, never approvals.
  One that ended left its issue Blocked: set it Ready again and start its
  autopilot (step 4), and the next session reads the answer in the issue.
  A session is named after its repo, as the workspace's `CLAUDE.md` says
  (Sessions), `<name>-<n>` when the autopilot started it; Herdr allows only
  `[a-z][a-z0-9_-]`:

  ```sh
  name=$(printf '%s' "<repo>" | sed -E 's/^\.//; s/\./-/g')
  ```
- **`Needs:`**: the change it names becomes an issue of its own, in that
  repo, or in `0xc0-labs/packages` for a package, written as a contract
  (step 2), and the session's issue is "blocked by" it (step 2's
  `--add-blocked-by`). It is gated and handed on like any other; once it
  is closed and applied, or the package published, the session's issue is
  gated again (step 3) and its autopilot started.
- **`Shared code:`**: weighed by Shared code, below.
- **A `.claude/` patch** goes to the operator as it is, with its branch;
  the issue stays In Progress meanwhile.
- **A PR marked ready**: reviewed (step 6).

**A blocker closes**: once it is applied too (step 3), gate what it
blocked and start that repo's autopilot again, the issues already Ready
included. An autopilot turns itself off while its repo's only Ready issues
are blocked, and does not start again by itself.

## 6. Review every ready PR

A ready PR can be merged (workspace#119), so each one is reviewed before
the operator merges it: a repo session's once it marks it ready, and the
orchestrator's own, from a subagent, before it marks it.

```sh
gh pr view <pr> -R 0xc0-labs/<repo> --json title,body,isDraft,headRefName
gh pr checks <pr> -R 0xc0-labs/<repo>
gh pr diff <pr> -R 0xc0-labs/<repo>
```

Against its issue: every acceptance criterion met, nothing out of scope,
the title a Conventional Commit for the change, `Closes`/`Refs` and the
merge order in the body, the workspace's rules kept, and no code another
repo already has (Shared code, below).

- **Its own PR**: its checks are watched in the background, at most once a
  minute, `gh pr checks <pr> -R 0xc0-labs/workspace --watch --interval 60`.
  Once they pass, the review finds nothing, and nothing in its issue is
  left, no `.claude/` patch for the operator included, the orchestrator
  marks it ready: `gh pr ready <pr> -R 0xc0-labs/workspace`. A finding goes
  back to the subagent that opened it, by message, or to a new one on the
  same branch.
- **A session's PR, on a finding**: comment it on the PR, what and where,
  for a session that knows nothing of this review; put the PR back to
  draft; set its issue Ready again; and start the repo's autopilot
  (step 4). A new session continues the branch, the PR's comments counting
  with the issue's.

  ```sh
  gh pr comment <pr> -R 0xc0-labs/<repo> --body-file <file>
  gh pr ready <pr> -R 0xc0-labs/<repo> --undo
  gh project item-edit 1 --owner 0xc0-labs --url <issue-url> --field Status --value Ready
  ```

No finding: the PR stays ready, for the operator to merge in the order
step 7 checks.

## 7. Integration, before calling it done

Green PRs in every repo are not a working change. Check, and say what was
checked:

- every PR of the set: reviewed (step 6) and ready, checks green,
  `Closes`/`Refs` right, the merge order in its body;
- every PR whose change touches a `.claude/`, the workspace's own included:
  the operator's commit of it is on the branch before saying it can merge,
  never after;

  ```sh
  gh pr view <n> -R 0xc0-labs/<repo> --json files --jq '.files[].path | select(startswith(".claude/"))'
  ```
- what one repo does to another: the callers of a reusable workflow that
  changed, the plan of a root that reads a policy that changed (it reads with
  the plan role, which must still reach it), a setting a repo inherits from
  the workspace, a plugin or hook a repo's session needs;
- the operator's steps, in order, in one list.

The parent issue closes when its last sub-issue does: through the workspace's
PR of the change when there is one, otherwise by hand, with a comment that
lists the sub-issues and their PRs.

## Shared code

Code two repos need alike lives once, as a package of `0xc0-labs/packages`
(the workspace's `CLAUDE.md`); when to extract one is the rule in the
workspace's `docs/design/delivery.md` (workspace#121). The orchestrator
weighs it when:

- a contract it writes would say "as in `<repo>`";
- two issues in different repos have the same outcome;
- a review (step 6) finds code duplicated across repos;
- a session reports a `Shared code:` line.

When the rule calls for a package, its extraction issue is written first,
in `packages`, as a contract (step 2), and every issue that will use it is
"blocked by" it: each contract names the package, not the repo the code
came from. A session's `Needs:` on a package is no longer a question to
weigh: its issue already waits on it (step 5).

## When GitHub rate-limits

On "rate limit" or "submitted too quickly" from any `gh` call, before
anything else:
[`references/github.md`, When GitHub rate-limits](../../references/github.md#when-github-rate-limits).

## Never

Edit any repo's file in its own session, the workspace's included, have a
subagent edit any repo but the workspace, merge, apply, write or rotate a
secret, or answer for the operator.
