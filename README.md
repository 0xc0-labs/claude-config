# claude-config

Claude Code marketplace and plugin for the `0xc0-labs` organization.

```
.claude-plugin/marketplace.json   the marketplace
plugins/0xc0/                  the plugin
plugins/software-architecture/ the architecture skills plugin
  skills/                         3 skills
  references/                     what more than one skill links to
  hooks/                          guardrails, commit and branch conventions, board loader
```

## Installing

Which repos enable it, and why each sets `autoUpdate`, is the workspace's
`CLAUDE.md` (Claude Code plugins). In the repo's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "0xc0-labs": {
      "source": { "source": "github", "repo": "0xc0-labs/claude-config" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": { "0xc0@0xc0-labs": true }
}
```

That declares and enables the plugin but does not install it. Once per
machine, from the workspace:

```bash
claude plugin marketplace add 0xc0-labs/claude-config
claude plugin install 0xc0@0xc0-labs --scope project
```

Then start a new session: plugins load at startup.

## Skills

| Skill          | What for                                                  |
|----------------|-----------------------------------------------------------|
| `vault-secret` | where a secret goes in Vault, how it is granted, written and rotated |
| `orchestrate`  | the workspace session: plans a change across repos, writes each repo's issue as its contract (parent and sub-issues, "blocked by", related issues), gates them to Ready, starts each repo's autopilot (again when a blocker closes), has a subagent in its own worktree make the workspace's own changes, files a session's `Needs:` as an issue its own is blocked by, weighs a shared package where code repeats across repos, reviews every ready PR (on a finding: a comment, back to draft, the issue Ready again), marks its own ready, marks ready a PR left a draft for another change once that change lands, checks the whole set |
| `work-issue`   | a repo's session: back on an up-to-date `main` (in its own worktree, the fetched `origin/main`) unless its own PR is open, claims the issue named (`<n>` or `<repo>#<n>`) or this repo's Ready issue of highest priority, works it up to a draft PR (in an application repo, around gentle-ai's own workflow), marks it ready once it can be merged (checks green, gentle-ai's review approved and acknowledged, nothing in the issue left, no `.claude/` patch for the operator, nothing it waits on still open) or says why it stays a draft, as where `gh pr ready` is denied, reports back in a fixed shape, takes the next; named as `<repo>#<n>`, as the autopilot does, works that one alone, grants gentle-ai's review without asking, and ends with a fixed last line |

They live in the plugin, not in a single repo, because they apply in all of
them: secrets show up everywhere, and every repo works the same way (the
workspace's `docs/design/how-we-work.md`). A repo's session, named as the
workspace's `CLAUDE.md` says (Sessions), starts working with
`claude -n <name> "/0xc0:work-issue"`. The workspace's autopilot, which the
orchestrator starts once it sets a repo's issues Ready, starts one fresh
session per issue, in its own worktree,
`claude --settings <hooks> -n <name>-<n> -w <name>-<n> "/0xc0:work-issue <repo>#<n>"`,
and closes it on its last line, `work-issue: done <repo>#<n>` or
`work-issue: stopped …`. Skills tied to one repo live in that repo's
`.claude/skills/` instead — see `infrastructure/`.

A repo session's report also names what reaches past its repo, for the
orchestrator to weigh. `Shared code:` when its work copies or follows code
another repo already has: it still finishes the issue, since a shared
package in `0xc0-labs/packages` is the orchestrator's call
(workspace#121). `Needs:` when the issue cannot be finished without a
change in another repo, a package included: it pushes what it has, sets
the issue Blocked and stops with `work-issue: stopped <repo>#<n>: needs …`,
never editing that repo or copying the package's code as a workaround.

A ready PR can be merged (workspace#119), so a PR whose work is done but
that may merge only after another change lands stays a draft: while its
issue has an open "blocked by", a sibling that merges first is still open,
or an upstream change it depends on is merged but not yet applied. The
report says on what, `draft: waits on <url> …`, the issue stays In
Progress, and the session ends as done. Once that change lands, the
orchestrator checks the PR again (checks still green, mergeable, nothing
else open), marks it ready, and tells the operator in the merge order.

What both `orchestrate` and `work-issue` do on GitHub, relating two issues
and backing off a rate limit, lives once in
[`plugins/0xc0/references/github.md`](plugins/0xc0/references/github.md),
and each skill links to it.

Claude Code replaces a bare `$1`, `$2`… in a `SKILL.md` with words of the
skill's arguments, so a snippet braces them, `"${1}"`, or uses a named
variable. A session's shell can be zsh, where arrays start at 1 and
`mapfile` does not exist, so no snippet uses one. In a worktree, Claude Code
refuses a command that runs git inside `$(…)` (claude-config#54), so no
snippet does: plain calls, and the session decides from what they print.
`hooks/tests/skills.sh` fails on any of the three, in the references too: a
reference is read, not expanded, but its snippets run in the same shell.
Nor does `work-issue` pass `gh` a title, a body or a comment on the command
line: there too, a text that names git is refused (claude-config#56), so it
goes in a file.

## The `software-architecture` plugin

Three skills a session loads when it designs or reviews application code:
`hexagonal-architecture`, `domain-driven-design` and `rest-api-design`.
Each is written from scratch and cites its primary sources (books, RFCs,
the OpenAPI specification, public API guidelines) by name and version.
The application repos enable it (the Next.js and Payload ones); the
infrastructure repos do not load it. The text was drafted with Opus
(workspace#151). Enable it as `0xc0` is, with
`"software-architecture@0xc0-labs": true` in `enabledPlugins`, and install it
with `claude plugin install software-architecture@0xc0-labs --scope project`.
Its version lives in its own `plugin.json`, and a change under it bumps it.

## Hooks

- `board.sh` — `SessionStart`: loads the org project board into every
  session, with the rule that no work starts without an issue, and never
  blocks one. In the workspace, the orchestrator's session, the whole board.
  In a repo's own session, that repo's Ready (by priority), In Progress and
  Blocked issues, and only counts for the rest. Every session shares the
  operator's token and so GitHub's limits: the board is read once for all of
  them, into `~/.cache/0xc0/board.json` (or under `$XDG_CACHE_HOME`), reused
  for 120 seconds, with a lock so sessions starting together read it once. A
  failed read leaves the last board with a note; a rate limit pauses reads
  for five minutes, since every request during GitHub's penalty extends it.
  A session the workspace's autopilot starts carries `OXC0_AUTOPILOT=1`
  (workspace#130) and gets no board: `work-issue` reads its issue and that
  issue's status itself, and with one session per issue, a whole read for
  each spent GitHub's hourly quota (claude-config#71). `board.sh` reads
  nothing then and prints one line saying so.
  `tests/board.sh` checks it against a stand-in `gh`.
- `no-apply.sh` — blocks `tofu/terraform apply|destroy`, and `ansible-playbook`
  or `scripts/ansible` without `--check`.
- `guard-files.sh` — blocks touching the state, and writing a secrets file
  (`.env`, `*secrets.yaml`, `*.sops.*`, private keys) into a repo: secrets live
  in Vault. gitops' `vault-secrets.yaml`, which only names Vault paths, is let
  through. It only sees Edit and Write: a file written from a
  shell command is not checked.
- `commit-msg.sh` — rejects a commit whose message, from `-m` (grouped flags
  such as `-qam` included) or from a heredoc through `-F -`, has a subject that
  is not a Conventional Commit, is over 72 characters, ends in a period,
  starts with a capital, or carries a `Co-Authored-By` / generated-by trailer.
- `branch-name.sh` — rejects creating a branch (`git switch -c`, `git checkout
  -b`, with or without `-C <dir>`) whose name is not `<type>/<slug>`: a commit
  type, then lowercase letters, digits, `.` and `-`.

Two more scripts sit beside them, but the plugin does not register them:
Claude Code creates a `claude -w` worktree before it loads plugins' hooks,
so a plugin's `WorktreeCreate` never runs for it (claude-config#52). The
workspace's autopilot declares both through `--settings` (workspace#105),
from the workspace's own checkout of this repo:

- `worktree-create.sh` — `WorktreeCreate`, which replaces Claude Code's own
  worktree logic: `claude -w <name>` gets a worktree beside its repo, at
  `<workspace>/.worktrees/<name>`. Under the repo, Node and TypeScript would
  resolve a module missing from the worktree in the primary clone's
  `node_modules`, and the primary clone's tools would walk into it
  (workspace#103). It fetches origin and adds the worktree detached at
  `origin/main`; `work-issue` creates or checks out the branch. It refuses a
  name that is not `[a-z0-9][a-z0-9._-]*`, and a repo not directly under a
  workspace that carries `CLAUDE.md`, the workspace itself included.
- `worktree-remove.sh` — `WorktreeRemove`: removes that worktree and prunes,
  never the primary clone. Claude Code leaves a hook-made worktree's branch
  behind, so it deletes the branch too, but only when origin holds all of
  it: an unpushed branch, the only copy of its commits, is kept.

They require `jq` and `perl` on the PATH. A hook blocks a tool call by
exiting 2, and Claude reads why from its stderr; 0 lets it through.
`hooks/tests/run.sh` runs every case in `hooks/tests/cases.jsonl` through its
hook and compares that exit code with the case's `want`, then runs
`board.sh`'s, every `hooks.json` command from a plugin path with a space,
the worktree scripts' (on a throwaway origin and workspace) and the
skills' checks; the `hooks` workflow runs it on every PR that
touches the hooks, the skills or the references.

## Versioning

The plugin's version lives in `plugins/0xc0/.claude-plugin/plugin.json`
alone: the marketplace entry declares none, since Claude Code takes
`plugin.json`'s over it without warning. Every change under `plugins/0xc0/`
bumps it (the workspace's `CLAUDE.md`, Claude Code plugins), and the
`plugin-version` workflow fails a PR that does not.

## Validate

```bash
claude plugin validate .
```
