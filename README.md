# claude-config

Claude Code marketplace and plugin for the `0xc0-labs` organization.

```
.claude-plugin/marketplace.json   the marketplace
plugins/0xc0/                  the plugin
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
| `orchestrate`  | the workspace session: plans a change across repos, writes each repo's issue as its contract (parent and sub-issues, "blocked by", related issues), gates them to Ready, wakes each repo's session, checks the whole set |
| `work-issue`   | a repo's session: back on an up-to-date `main` (in its own worktree, the fetched `origin/main`) unless its own PR is open, claims the issue named (`<n>` or `<repo>#<n>`) or this repo's Ready issue of highest priority, works it up to a draft PR (in an application repo, around gentle-ai's own workflow), reports back in a fixed shape, takes the next; named as `<repo>#<n>`, as the autopilot does, works that one alone and ends with a fixed last line |

They live in the plugin, not in a single repo, because they apply in all of
them: secrets show up everywhere, and every repo works the same way (the
workspace's `docs/design/how-we-work.md`). A repo's session, named as the
workspace's `CLAUDE.md` says (Sessions), starts working with
`claude -n <name> "/0xc0:work-issue"`. The workspace's autopilot starts one
fresh session per issue, in its own worktree,
`claude --settings <hooks> -n <name>-<n> -w <name>-<n> "/0xc0:work-issue <repo>#<n>"`,
and closes it on its last line, `work-issue: done <repo>#<n>` or
`work-issue: stopped …`. Skills tied to one repo live in that repo's
`.claude/skills/` instead — see `infrastructure/`.

What both `orchestrate` and `work-issue` do on GitHub, relating two issues
and backing off a rate limit, lives once in
[`plugins/0xc0/references/github.md`](plugins/0xc0/references/github.md),
and each skill links to it.

Claude Code replaces a bare `$1`, `$2`… in a `SKILL.md` with words of the
skill's arguments, so a snippet braces them, `"${1}"`, or uses a named
variable. A session's shell can be zsh, where arrays start at 1, so no snippet
uses one. In a worktree, Claude Code refuses a command that runs git inside
`$(…)`, so no snippet does: plain calls, and the session decides from what
they print. `hooks/tests/skills.sh` fails on any of the three. Nor does
`work-issue` pass `gh` a title, a body or a comment on the command line:
there too, a text that names git is refused (claude-config#56), so it goes
in a file.

## Hooks

- `board.sh` — `SessionStart`: loads the org project board into every
  session, with the rule that no work starts without an issue. In the
  workspace, the orchestrator's session, the whole board. In a repo's own
  session, that repo's Ready (by priority), In Progress and Blocked issues,
  and only counts for the rest. Every session shares the operator's token and
  so GitHub's limits: the board is read once for all of them, into
  `~/.cache/0xc0/board.json` (or under `$XDG_CACHE_HOME`), reused for 120
  seconds, with a lock so sessions starting together read it once. A failed
  read leaves the last board with a note; a rate limit pauses reads for five
  minutes. `tests/board.sh` checks it against a stand-in `gh`.
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
  `node_modules`, and the primary clone's tools would walk into it. It
  fetches origin and adds the worktree detached at `origin/main`;
  `work-issue` creates or checks out the branch. It refuses a name that is
  not `[a-z0-9][a-z0-9._-]*`, and a repo not directly under a workspace that
  carries `CLAUDE.md`, the workspace itself included.
- `worktree-remove.sh` — `WorktreeRemove`: removes that worktree and prunes,
  never the primary clone. Claude Code leaves a hook-made worktree's branch
  behind, so it deletes the branch too, but only when origin holds all of
  it: an unpushed branch is kept.

They require `jq` and `perl` on the PATH. `hooks/tests/run.sh` runs every case
in `hooks/tests/cases.jsonl` through its hook, then `board.sh`'s, the
worktree scripts' (on a throwaway origin and workspace) and the skills'
checks; the `hooks` workflow runs it on every PR that touches the hooks, the
skills or the references.

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
