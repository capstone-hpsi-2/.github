# agents/

The source of the agent rules, skills and guard files that `admin-backend`, `transcription-backend` and `frontend` share. Each of those repos copies them with its `scripts/sync-agents.sh`, at the `.github` commit pinned in its `agents.lock.json`.

| Here | In each repo |
|---|---|
| `AGENTS.shared.md` | `AGENTS.md`, between the `BEGIN SHARED` and `END SHARED` markers |
| `skills/<name>/` | `.agents/skills/<name>/`, copied again to `.claude/skills/<name>/`. Every folder here is shared; the sync writes their names into the `skills` list of `agents.lock.json`. |
| `claude/settings.json` | `.claude/settings.json`: deny rules for the generated paths, and the hook that runs the guard |
| `antigravity/hooks.json` | `.agents/hooks.json`: the same hook for Antigravity |
| `scripts/agents-guard.sh` | `scripts/agents-guard.sh`: refuses agent edits to generated files and says where the change goes |
| `tests/` | not copied; CI for this repo |

## How a change reaches the repos

1. A PR here changes a file in `agents/`. CI runs the guard tests and the skill frontmatter check.
2. After merge, each repo's `agents` workflow runs daily (or by hand), pins the new `main` commit, runs the sync and opens or updates one PR on branch `chore/sync-agents`.
3. A member reviews and merges that PR. Until then the repo keeps the old pin, and its CI checks against it.

## What stops a wrong edit

| Layer | Where | What it does |
|---|---|---|
| Rules | the shared block | tells agents which files are generated and where changes go |
| Claude Code deny rules | `.claude/settings.json` | refuses Edit and Write on the fixed generated paths |
| Hook | `.claude/settings.json`, `.agents/hooks.json` | runs `scripts/agents-guard.sh` before each file edit; refuses edits to generated files, including changes to the shared block of `AGENTS.md`, and names the right place |
| CI | each repo's `agents` workflow | `sync-agents.sh --check` fails a PR whose generated files differ from the pin |

The hook sees only the agents' file tools. Shell commands, editors and `sync-agents.sh` itself are not stopped; CI catches what gets past.

This repo is public: no secrets or clinical details.
