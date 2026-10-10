# AGENTS.md: .github

This repo is the source of the shared agent files. Edit them here, in `agents/`; never in `admin-backend`, `transcription-backend` or `frontend`, where they are generated copies. The layout and how a change reaches those repos: [agents/README.md](agents/README.md).

Read [agents/AGENTS.shared.md](agents/AGENTS.shared.md) before any change: its rules apply here too (branch, PR, comments, no secrets or clinical data; this repo is public). Claude Code loads it through the next line.

@agents/AGENTS.shared.md

## .github specifics
- Its Gates table has this repo's gate. The `all` row does not apply here: this repo is the source and has no `scripts/sync-agents.sh` of its own.
- Change `main` only through a merged PR from a `feat/` branch (skill `create-pr`; read it from `agents/skills/create-pr/SKILL.md`, this repo does not install skills).
- Merged changes reach the other repos through their `chore/sync-agents` PR (flow: `agents/README.md`). Do not open sync PRs there by hand unless asked.
- A new or renamed skill: the folder name equals `name:` in its `SKILL.md`, and the Skills table in `agents/AGENTS.shared.md` gets its row. `agents/tests/skills-frontmatter.sh` checks both. A renamed or removed skill's old name goes in `agents/skills-retired`.
- A change to `agents/scripts/agents-guard.sh` comes with a case in `agents/tests/agents-guard.test.sh`; a change to `agents/scripts/sync-agents.sh`, with a check in `agents/tests/sync-agents.test.sh`.
- `CLAUDE.md` contains only `@AGENTS.md`; there is no `GEMINI.md`.
