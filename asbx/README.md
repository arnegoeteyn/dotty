# copilot-sbx

AI coding agents in Docker Sandboxes, one sandbox per repo and harness
(`copilot` and `pi`).

Each sandbox (`<harness>-<repo>`) works on a private clone of its repo and has
read-only access to all other repos. GitHub is read-only for it: it can
clone and fetch (e.g. private Go modules), but it can't push or write through
the GitHub API.

## Layout

- `../repos.yaml` (dotty root, shared with wezterm): the list of repos (`url`, optional `path`, default `<root>/<name>`).
  Missing ones are cloned by `./asbx sync`.
- `shared/`: used by every harness, mounted read-only into every sandbox.
  - `base.sbxenv.yaml`: memory, `github` secret, kits, lockdown, git hook setup.
  - `kits/go/`: installs `gopls`, `golangci-lint` and `just`, sets up private
    module access and native-arch testcontainers (Go itself is in the image).
  - `scripts/notify.sh`: agent hook that shows a macOS notification via OSC 9
    on the attached terminal (WezTerm needs notification permission in macOS).
  - `scripts/prepare-repo.sh`: runs once per new sandbox; builds the repo's
    custom linter (`preparelint`) and mocks (`mocks`) if it has those recipes.
  - `lsp.yaml`: language servers; rendered per harness.
  - `skills/<name>/SKILL.md`: agent skills, shared by all harnesses. Files are
    Go templates filled from `repos.yaml` (e.g. `{{range .Repos}}`). The
    global `sbx skills` store is turned off for these sandboxes.
  - `workflow.md`: the agent's rules (branch workflow, sandbox limits).
    Edit this one; it's rendered per harness.
  - `../learnings/` (top level, not under `shared/`): `STYLE_GUIDE.md`
    (hand-maintained), `meta.md` (the structure) and `lessons/` (one file per
    lesson, written by the `archivist` agent via pi's `/feedback`). Read by
    pi's subagents; the lead queries it through the archivist. Mounted read-write only for harnesses listing it in
    `writable:`; `{{.Learnings}}` in templates points here.
  - `hooks/pre-commit`: only allows commits on `agent/*` branches.
  - `hooks/commit-msg`: strips `Co-authored-by:` trailers.
- `harnesses/<name>/`: agent-specific bits.
  - `sbxenv.yaml`: agent, secrets, how it finds the instructions.
  - `harness.yaml`: how `workflow.md`, `lsp.yaml`, `skills/` and `hooks/` are
    rendered for this agent and where the agent reads them.
  - `hooks/`: agent hook configs (templates, `{{.Shared}}` = `shared/`). For
    copilot: notify on questions, permission prompts, errors and end of turn.
  - `files/`: extra config files (templates), linked to the `files:` targets in
    `harness.yaml`, or copied once at create with `copy: true` (for files the
    agent writes itself).
  - more directories (templates), each linked to its target via `dirs:` in
    `harness.yaml`, like `hooks/`.
  - `kits/`: harness-only kits.
- `harnesses/pi/`: pi from the `docker.io/sbx/pi-kit` image. `kits/copilot`
  binds the `copilot` secret so the proxy adds the real token on
  `api.githubcopilot.com` (pi only sees a placeholder `COPILOT_GITHUB_TOKEN`);
  `files/models.json` points pi at that host instead of
  `api.individual.githubcopilot.com`, and `files/settings.json` makes Copilot
  the default provider. `extensions/`: pi extensions (`*.ts` or dirs with
  `index.ts`), linked to `~/.pi/agent/extensions` via `hooks.dir`; rendered as
  templates, so avoid a literal `{{`. `extensions/notify.ts` calls
  `shared/scripts/notify.sh` when a run ends, fails or waits for input;
  `extensions/usage.ts` adds `/usage` (Copilot quota and session tokens);
  `extensions/subagent/` is pi's example subagent extension (a `subagent` tool
  that runs agents as separate `pi` processes, single, parallel or chained).
  `agents/` (linked to `~/.pi/agent/agents`) holds those agents (scout,
  architect, refactorer, implementer, test-writer, wizard, reviewer, pruner,
  archivist, committer), and `prompts/` (linked to `~/.pi/agent/prompts`) adds
  `/lead <request>` (orchestrate them: scout, design, approval, implement,
  review, prune, then the haiku `committer` commits; it asks the archivist what we've learned) and `/feedback <complaint>`. No LSP yet.
- `scripts/lockdown.sh`: network deny rules (push, SSH, API writes), run once
  per new sandbox.
- `projects/`, `generated/`: written by `./asbx sync`, gitignored.

## One-time host setup

Needs `sbx` (`brew install docker/tap/sbx`, then `sbx login`), `gh` logged in
(`gh auth login`, used for the sandbox tokens), `go` and `just`.

    sbx settings set ssh.agentForwardingEnabled false   # don't forward SSH keys (global)
    sbx settings set env.rememberHostCommands true      # approve the plan once, not every run
    sbx daemon restart                                  # stops all running sandboxes

Done automatically per sandbox, no action needed:

- secrets (`github`, plus e.g. `copilot`) from `gh auth token`, scoped to the sandbox
- deny rules from `scripts/lockdown.sh`, scoped to the sandbox (`sbx policy ls <harness>-<repo>`)
- a `sandbox-<harness>-<repo>` git remote in the host repo, removed by `./asbx rm`

## Usage

- `just build`: builds the `./asbx` tool (rerun after editing `main.go`).
- `./asbx sync`: clones missing repos and generates `generated/` and
  `projects/` for all harnesses. Nothing else writes these files.
- `./asbx run <repo> [--harness NAME]`: create if needed, then attach
  (`create`, `plan`, `rm` also work). Default harness is `pi`.
  `run`, `create` and `plan` refuse to start if `repos.yaml`, `shared/` or
  `harnesses/` changed since the last sync. `rm` always works.
  `./asbx` with no arguments lists the repos and harnesses and whether a sync
  is needed.

After editing:

| You edit | Then |
|---|---|
| `workflow.md`, `lsp.yaml`, skills, git hooks, agent hook files, `dirs:` contents | `./asbx sync`; applies to the next agent session |
| `learnings/` | nothing; the sandbox sees the change live |
| `env` in a sbxenv file | `./asbx sync`; applies on the next `./asbx run` |
| `../repos.yaml`, kits, other sbxenv settings, adding `hooks:` or `dirs:` entries to a harness | `./asbx sync`, then recreate (`./asbx rm <repo>`, `./asbx run <repo>`) |
| `main.go` | `just build` |

## Branch workflow

- "Implement X": the agent fetches your `main` (or a branch you name, or
  "my current branch") as `host/<branch>`, creates `agent/<description>` from
  it and commits there.
- "Look at my current branch" / "review nova-1092": the agent fetches it as
  `host/<branch>` and reviews it against `host/main` without committing.
  Commit your work first; uncommitted changes aren't visible to it.

Review the agent's branches (from the repo's host checkout):

    git fetch sandbox-pi-<repo>
    git diff main..sandbox-pi-<repo>/agent/<description>

Removing a sandbox keeps its branches on the host under
`refs/sandboxes/<sandbox>/`. Don't `git fetch --prune` the sandbox remote:
it also prunes those saved refs.
