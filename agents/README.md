# agents/

The source of the agent rules, skills and guard files that `admin-backend`, `transcription-backend` and `frontend` share. Each of those repos copies them with its `scripts/sync-agents.sh`, at the `.github` commit pinned in its `agents.lock.json`.

| Here | In each repo |
|---|---|
| `AGENTS.shared.md` | `AGENTS.md`, between the `BEGIN SHARED` and `END SHARED` markers |
| `skills/<name>/` | `.agents/skills/<name>/`, copied again to `.claude/skills/<name>/`. Every folder here is shared; the sync writes their names into the `skills` list of `agents.lock.json`. |
| `skills-retired` | names of renamed or removed shared skills; the sync deletes those folders |
| `claude/settings.json` | `.claude/settings.json`: deny rules for the generated paths, and the hook that runs the guard |
| `antigravity/hooks.json` | `.agents/hooks.json`: the same hook for Antigravity |
| `scripts/agents-guard.sh` | `scripts/agents-guard.sh`: refuses agent edits to generated files and says where the change goes |
| `scripts/sync-agents.sh` | `scripts/sync-agents.sh`: the sync itself, so a change to what is synced reaches every repo in one PR here |
| `workflows/agents.yml` | `.github/workflows/agents.yml`. In CI it is copied only when the repo has the `SYNC_TOKEN` secret (`AGENTS_SYNC_WORKFLOW=1`): `GITHUB_TOKEN` may not push workflow files. `--check` only warns about it |
| `tests/` | not copied; CI for this repo |

## How a change reaches the repos

1. A PR here changes a file in `agents/`. CI runs the guard tests, the sync tests and the skill frontmatter check.
2. On merge, `.github/workflows/agents-dispatch.yml` here sends the `agents-changed` repository_dispatch to each app repo.
3. That repo's `agents` workflow pins the new `main` commit, runs the sync and opens or updates one PR on branch `chore/sync-agents`. It runs again on every push to the repo's own `main`, so the PR is rebuilt on the new base and never conflicts, and daily as a backstop for a lost dispatch. Runs queue in one concurrency group.
4. A member reviews and merges that PR; its CI runs like any PR's. Until then the repo keeps the old pin, and its CI checks against it.

Dispatches, cross-repo checkouts and the sync PR use the `SYNC_TOKEN` repo secret, a member's fine-grained PAT with Contents, Pull requests and Workflows read and write on the four repos. Without it the sync falls back to `GITHUB_TOKEN`: the PR leaves `.github/workflows/agents.yml` out and runs no CI until closed and reopened, and the dispatch fails, leaving the daily run.

The backends' API contracts reach the frontend the same way: `.github/workflows/contract-frontend.yml` here, called from each backend's CI, typechecks frontend `main` against a backend PR's `openapi/` specs and, on merge, sends `contracts-changed` to the frontend, which opens or updates `chore/sync-contracts`.

## What stops a wrong edit

| Layer | Where | What it does |
|---|---|---|
| Rules | the shared block | lists the generated files and where each change goes instead |
| Claude Code deny rules | `.claude/settings.json` | refuses Edit and Write on the fixed generated paths, with a generic message; they still hold where bash or python is missing |
| Hook | `.claude/settings.json`, `.agents/hooks.json` | runs `scripts/agents-guard.sh` before each file edit; refuses edits to generated files and to second rule homes, including changes to the shared block of `AGENTS.md`, and names the right place |
| CI | each repo's `agents` workflow | `sync-agents.sh --check` fails a PR whose generated files differ from the pin |

The hook sees only the agents' file tools. Shell commands, editors and `sync-agents.sh` itself are not stopped; CI catches what gets past.

## Sessions started above the repos

Claude Code loads `.claude/settings.json` only from the folder a session starts in, and Antigravity reads `.agents/hooks.json` only from the open workspace. A session started in a folder that holds several repos therefore runs no hook. For Claude Code, add this to `~/.claude/settings.json`, with the path of any one consumer checkout (the guard finds the repo from the edited file, so one copy covers all of them):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "shell": "bash",
            "command": "AGENTS_GUARD_SCOPE=user bash \"<checkout>/scripts/agents-guard.sh\"",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

`AGENTS_GUARD_SCOPE=user` makes it step aside when the session's own repo hook already runs. Antigravity also reads a user-level `~/.gemini/config/hooks.json`, but that form is untested; open the repo folder as the workspace instead.

This repo is public: no secrets or clinical details.
