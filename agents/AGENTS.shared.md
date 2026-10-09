## Shared rules (all capstone-hpsi-2 repos)

- `admin-backend`: FastAPI. Only JWT issuer, RBAC, realtime `/ws`, `deploy/`, schema `admin`.
- `transcription-backend`: the `/ai/*` API (`app/`) and the GPU worker (`worker/`); layout in its `docs/DESIGN.md`.
- `frontend`: React + TypeScript PWA and the nginx edge. API types come from the vendored `contracts/`.
- `.github`: org templates, the reusable `contract-health` workflow, and `agents/`: the source of this block, the shared skills and the agent guard files.

### Guardrails
Nothing on GitHub enforces these (no branch protection on our plan), so follow them literally.

1. `main` changes only through a merged PR. Never commit on, push to, or force-push `main`. Never `--no-verify`.
2. Branch: `feat/<member>-<featname>`, member in `andrew jered jeremiah jingkai darryl shana`, featname kebab-case. Example: `feat/shana-claim-long-poll`. The one other branch is `chore/sync-agents`, owned by the daily agents sync job: never commit to it by hand.
3. Before a PR: `git fetch origin && git rebase origin/main`, run the repo gate on the rebased tree, then an adversarial self-review by your own independent subagents (skill `create-pr`).
4. Names say what the thing is, units included: `claim_next_job`, `lease_timeout_s`. Not `handle`, `data2`, `utils2.py`.
5. Comments explain WHY or HOW, never WHAT. Delete WHAT comments on lines you touch.
   ```python
   # BAD: increment attempts
   job.attempts += 1
   # GOOD: counted at claim, not on failure, so a worker that dies mid-job still burns an attempt.
   job.attempts += 1
   ```
6. No secrets or clinical data (audio, transcripts, note text, names, dates of birth, photos) in the repo, logs, fixtures, commits, issues, PR bodies, or any prompt or request that leaves our servers. Log ids and counts only.
7. No performance or quality figure (latency, RTF, VRAM, WER, ...) in code, docs or PRs unless measured; cite the results file. Published figures say "published" and link the source.
8. Never write rules into `CLAUDE.md` or `GEMINI.md`. `CLAUDE.md` contains only `@AGENTS.md`; there is no `GEMINI.md`.

### One home per fact
Each fact lives in one file. Elsewhere, link to it; never restate it.

| Kind of info | Home |
|---|---|
| Rules for agents in every repo | `.github` repo, `agents/AGENTS.shared.md` (this block) |
| Rules for agents in one repo | that repo's `AGENTS.md`, `## <repo> specifics` |
| Multi-step procedures | a skill in `.agents/skills/<name>/SKILL.md` |
| What a repo is, how to run it | that repo's `README.md` |
| Transcription design: data, lifecycle, jobs, security, API plan. Update when a route, table, column, flow or security rule changes | `transcription-backend/docs/DESIGN.md` |
| Models, test data, measurements, results. Update when a component, model, revision, parameter, placement or dataset changes | `transcription-backend/docs/EXPLORATION.md` |
| HTTP API contract | each backend's generated `openapi/openapi.yaml` |
| Realtime events | `admin-backend/openapi/asyncapi.yaml` |
| Env variable names | `admin-backend/deploy/.env.example` |
| Schema `admin` | `admin-backend/migrations/` |
| Diagrams (flow, ER, deployment, architecture) | the team Miro board. No diagram copies in repos. |

Once code exists for something a doc describes (routes, tables, templates), the code is the home and the doc links to it.

### Cascade
- A changed decision updates its one home in the same PR and removes every stale mention. Before the PR, grep all three repos for the old term: `git grep -n "<old term>"`.
- A backend route or schema change regenerates `openapi/openapi.yaml` (`python -m app.export_openapi`) in the same PR. The frontend then bumps `contracts.lock.json` and runs `./scripts/sync-contracts.sh`.

### Generated files
`scripts/sync-agents.sh` writes these from `capstone-hpsi-2/.github` `agents/`; never edit them in a repo: this block, the shared skills listed in `agents.lock.json`, `.claude/skills/` (a copy of `.agents/skills/`, since Claude Code reads skills only there), `CLAUDE.md`, `.claude/settings.json`, `.agents/hooks.json`, `scripts/agents-guard.sh`. A hook refuses agent edits to them and names the right place; `sync-agents.sh --check` in CI backs it up. To change a shared rule or skill, or when unsure where a rule goes: skill `agents-md-placement`. Merged `.github` changes arrive through a daily PR on `chore/sync-agents`; review and merge it like any PR.

### Skills
Repo-local skills go in `.agents/skills/<name>/SKILL.md`.

| Skill | Use when |
|---|---|
| `create-pr` | Before the first edit of any change (feature, fix, code, config, docs), and to finish it: branch, rebase, gate, self-review, PR. |
| `pr-review` | Reviewing or explaining someone else's PR. |
| `agents-md-placement` | A rule or lesson needs a home. |

### Gates (what CI runs; from the repo root)

| Repo | Gate |
|---|---|
| `admin-backend` | `ruff check . && ruff format --check . && python -m app.export_openapi --check && APP_ENV=ci pytest -q`. Full stack: `./deploy/smoke-test.sh --local`. |
| `transcription-backend` | `ruff check . && ruff format --check . && python -m app.export_openapi --check && pytest -q` |
| `frontend` | `npm ci && npm run lint && GITHUB_TOKEN=$(gh auth token) npm run contracts:check && npm run typecheck && npm run build` |
| `.github` | `bash agents/tests/agents-guard.test.sh && bash agents/tests/skills-frontmatter.sh` |
| all | `bash scripts/sync-agents.sh --check` (while `agents.lock.json` has `"sha": "BOOTSTRAP"`: `--local ../.github --check`) |

Python 3.12 (`pip install -r requirements-dev.txt`), Node 22. The frontend has no `test` script: say "no frontend tests exist", never "tests pass".
