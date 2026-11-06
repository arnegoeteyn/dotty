---
name: interpret-pi-session
description: Read and interpret recorded pi sessions (JSONL transcripts in ~/.pi/agent/sessions), including the user's /note verdicts, lead/subagent orchestration and what went wrong. Use when the user asks to look at, review or explain a pi session, a sandbox session (e.g. "the latest ddc session", "the ddc sandbox session from this morning"), or a note they left on one.
---

# Interpreting pi sessions

## Where sessions live

The root is `~/.pi/agent/sessions` on the host, with one directory per origin:

- `asbx-<harness>-<repo>`: sessions from an asbx sandbox, e.g. `asbx-pi-ddc`,
  `asbx-pi-dotty`, `asbx-pi-tf-alm`. If the user says "ddc session" or "ddc
  sandbox session", look in `asbx-pi-ddc`. The same goes for any other repo:
  "<repo> session" means `asbx-pi-<repo>`.
- `--Users-arne-...--`: sessions pi ran directly on the host. The name is the
  cwd with `/` replaced by `-`.

Inside a sandbox, `~` is `/home/agent`, so don't rely on `~` there. Only the
sandbox's own session dir is mounted, and `$PI_CODING_AGENT_SESSION_DIR`
points at it. Use `dirname "$PI_CODING_AGENT_SESSION_DIR"` as the root if
it's set, and `~/.pi/agent/sessions` otherwise. If the directory the user asks
about isn't there, say that it isn't mounted in this sandbox instead of
guessing.

## Finding a session by time

Files are named `<start timestamp>_<session id>.jsonl`, e.g.
`2026-11-06T08-59-09-081Z_01a1b015-....jsonl`. The timestamp is when the
session started, in **UTC** (`Z`), with `:` and `.` replaced by `-`. The user
is in Belgium (CET, UTC+1; CEST, UTC+2 in summer), so convert "this
morning" or "around 10" before matching.

- Most recent session: `ls <dir> | sort | tail -1`. Names sort
  chronologically.
- Last activity is the file's mtime (`ls -lt`). A long session can start
  earlier but end later than another.
- For a time range, filter the names by prefix, e.g. `ls <dir> | grep '^2026-11-06T0[89]'`.
- If several sessions fit and it's ambiguous, list them with their first user
  message and ask, or pick the obvious one and say which you picked.

## File format

Each line is one JSON entry: `type`, `id`, `parentId`, `timestamp`.

- Line 1 is `type: "session"` with `cwd`, which tells you the repo it ran in.
- Entries form a tree through `parentId`. Usually that's a chain, but if the
  user branched with `/tree`, several entries share a parent. Follow the
  `parentId` chain back from the last entry to get the path the user actually
  ended on.
- `type: "message"`: `.message.role` is `user`, `assistant`, `toolResult` or
  `system`. `.message.content` is an array of parts: `text`, `thinking`
  (the model's reasoning; useful for *why* it did something), and `toolCall`
  (`name`, `arguments`). Tool results carry `.message.toolName` and
  `.message.details`.
- `type: "custom"` with `customType`: extension entries that are shown in the
  transcript but **never sent to the model**:
  - `note`: see below.
  - `subagent-stats`: runs, turns, tokens and cost per subagent, written
    when a run that used subagents settles.
- `model_change` and `thinking_level_change`: settings switches.

Overview of a session (one line per entry, content truncated):

```sh
jq -c '{type, id, parentId, customType, role: .message.role,
  content: (.message.content // .data | tostring | .[0:800])}' <file>
```

## Notes

The user leaves notes with `/note <text>`, added by `harnesses/pi/extensions/note.ts`. A
note is a `custom` entry with `customType: "note"` and `data.text`. The model
never sees it, so the agent in that session didn't react to it. It's the
user's verdict for reviewing the setup afterwards: what went wrong, what was
good, what they did with the result.

```sh
jq -c 'select(.customType == "note") | {id, parentId, timestamp, text: .data.text}' <file>
```

A note refers to what happened **before** it, usually the whole run up to its
`parentId` and mostly the last turn. When asked to explain a note:

1. Read the note, then the whole transcript up to it, including the
   `thinking` parts. The reason something happened is usually stated there.
2. Compare what happened against the instructions the agent had: the
   expanded prompt in the first user message, `AGENTS.md`
   (`shared/workflow.md`), and the agent definitions.
3. Explain the cause: which instruction was ignored or misread, which
   wording let it happen, and what led the model there. Quote the relevant
   thinking and instructions. Then suggest concrete changes to the prompts
   or setup.

The setup's source lives in the dotty repo under `asbx/`:
`harnesses/pi/prompts/` (`lead.md`, `feedback.md`),
`harnesses/pi/agents/*.md`, `harnesses/pi/extensions/`, and
`shared/workflow.md`. On the host that's `~/Documents/dotty/asbx`. In a
sandbox, see the `repos` skill for where the dotty repo is.

## Lead-based vs non-lead sessions

**Lead-based** sessions were started with `/lead <request>`. The first user
message begins with `For this request, act as the Lead:` followed by the full
lead prompt (phases: sync, archivist, scout, architect, approval gate,
implement plus test-writer, review per task, prune, committer, full test
suite). The lead does nothing itself except git and tests. All other work goes
through the `subagent` tool, and there's a `subagent-stats` entry at the end.
For these sessions:

- Check the phases against the prompt: skipped steps (architect, approval
  gate, review per task), work the lead did itself instead of delegating,
  the wrong implementer tier, `wizard` without asking, missing archivist
  answers in tasks.
- Subagents run as separate `pi --no-session` processes, so they have **no
  session files of their own**. Their full conversations are in the
  `subagent` tool result's `.message.details.results[]`, with `agent`,
  `task`, `exitCode`, `messages`, `usage`, `model` and `stopReason`. The
  `content` text is only the final answer.

  ```sh
  # each subagent run: agent, exit code, task
  jq -c 'select(.message.toolName == "subagent") | .message.details.results[]
    | {agent, exitCode, model, task: .task[0:300]}' <file>
  # full conversation of one run: pick it by tool call id or by agent
  jq -c 'select(.message.toolName == "subagent") | .message.details.results[]
    | select(.agent == "reviewer") | .messages[]
    | {role, content: (.content | tostring | .[0:800])}' <file>
  ```
- `/feedback` sessions (first user message `The user's feedback is: ...`)
  are a variant: the lead hands the complaint to the `archivist`.

**Non-lead** sessions are plain prompts. One agent works directly with
`read`, `bash`, `edit` and so on, following `AGENTS.md`, usually without
subagents. Judge them by the request and `AGENTS.md`/`workflow.md` (branch
workflow, sandbox limits, tests). Don't hold them to lead phases that weren't
asked for.
