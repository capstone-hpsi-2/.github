# AGENTS.md: .github

This repo is the source of the shared agent files. Edit them here, in `agents/`; never in `admin-backend`, `transcription-backend` or `frontend`, where they are generated copies. The layout and how a change reaches those repos: [agents/README.md](agents/README.md).

- The rules in [agents/AGENTS.shared.md](agents/AGENTS.shared.md) apply here too: branch, PR, comments, no secrets or clinical data (this repo is public). Its Gates table has this repo's gate.
- Change `main` only through a merged PR from a `feat/` branch (skill `create-pr`; read it from `agents/skills/create-pr/SKILL.md`, this repo does not install skills).
- Merged changes reach the other repos through their daily `chore/sync-agents` PR. Do not open sync PRs there by hand unless asked.
- A new or renamed skill: the folder name equals `name:` in its `SKILL.md`, and the Skills table in `agents/AGENTS.shared.md` gets its row. `agents/tests/skills-frontmatter.sh` checks both.
- A change to `agents/scripts/agents-guard.sh` comes with a case in `agents/tests/agents-guard.test.sh`.
- `CLAUDE.md` contains only `@AGENTS.md`; there is no `GEMINI.md`.
