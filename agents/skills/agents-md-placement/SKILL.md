---
name: agents-md-placement
description: Decide where a new rule, convention, fact or lesson belongs in the capstone-hpsi-2 repos - the shared AGENTS.md block, one repo's specifics section, a skill, a human doc, or nowhere. Use for "add this to AGENTS.md", "remember this rule", "we should always/never ...", "make this a skill", "document this", or after a mistake a written rule would have prevented.
---

# Where does it go?

`AGENTS.md` is loaded into every agent session, so every line costs on every task. A skill costs only its description until used. Human docs are for people; agents read them only when linked.

## Human doc or AGENTS.md?
- **Human doc** (`README.md`, `docs/DESIGN.md`, `docs/EXPLORATION.md`): what the system is and why. Facts a teammate needs to understand or maintain it. Plain English, no agent procedures.
- **AGENTS.md or a skill**: how an agent must act when changing code: invariants, gate commands, procedures.
- A fact goes in one place only. If an agent needs a design fact, `AGENTS.md` links to the doc; it does not restate it. The doc map is under "One home per fact" in `AGENTS.md`.

## Decision table (first "yes" wins)

| # | Question | Home |
|---|---|---|
| 1 | Can it be read from the code, config or CI file (`pyproject.toml`, `ci.yml`)? | Nowhere. A copy drifts. |
| 2 | Is it a fact about the system for people (design, data, models, results)? | Its human doc, per the doc map. |
| 3 | Is it a procedure of more than ~5 lines, or needed for only one kind of task? | A skill in `.agents/skills/<name>/SKILL.md`: shared (in `.github`, plus a row in its Skills table) if 2+ repos use it, else repo-local (where to list it: "Skills" in `AGENTS.md`). |
| 4 | Does it apply to 2+ repos? | The shared block: PR to `.github` `agents/AGENTS.shared.md`. |
| 5 | Otherwise | That repo's `## <repo> specifics`, below `<!-- END SHARED -->`. |

Write rules as one imperative line, with the reason when it is not obvious.

## Changing a shared rule or skill
1. PR to `capstone-hpsi-2/.github` (skill `create-pr`), editing `agents/AGENTS.shared.md`, `agents/skills/<name>/`, or another synced file in `agents/` (layout: `agents/README.md`). A new shared skill also needs a row in the Skills table; a renamed or removed one goes in `agents/skills-retired`.
2. After merge, each repo's daily `agents` workflow opens or updates one PR on `chore/sync-agents`. Review and merge it. To adopt sooner, run the workflow by hand (Actions, `agents`, Run workflow), or on a `feat/` branch:
   ```bash
   bash scripts/sync-agents.sh --latest --check   # preview, writes nothing
   bash scripts/sync-agents.sh --latest           # pin, then rewrite every generated file
   git status --short                             # stage exactly these paths
   ```
3. Preview a `.github` change before it merges: `bash scripts/sync-agents.sh --local ../.github` in a scratch branch, never committed.

## Examples
- "Run an Alembic up/down/up round trip on Postgres before a migration PR." Both backends use Alembic: **shared block**, one line.
- "`worker/` never imports sqlalchemy, asyncpg or redis." Only transcription-backend has a worker: **transcription-backend specifics**, with the check `grep -rnE "sqlalchemy|asyncpg|redis" worker/`.
- "How to run the bench on JupyterHub" (many steps, only when benchmarking): **repo-local skill**.
- "The case note has statuses draft, approved, final." A design fact: **`docs/DESIGN.md`**; agents link to it.
- "Python lines are at most 100 characters." Already in `pyproject.toml` and enforced by ruff: **nowhere**.
