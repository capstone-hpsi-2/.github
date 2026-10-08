---
name: feature-branch
description: Start, resume, or finish a feature branch in admin-backend, transcription-backend or frontend. Use for "start a feature", "new branch", "continue my branch", "rebase on main", "get this ready for a PR", "open a PR", "push my work". Covers branch naming, rebasing on origin/main, the repo gate, the adversarial self-review with subagents, and gh pr create. Not for reviewing someone else's PR (use pr-review).
---

# Feature branch

Commands are Bash and run in Git Bash on Windows and on Linux. On Windows use `python`, not `python3` (often a Store stub).

## Stop rules (check every time)
Refuse and explain if the next step would:
- commit or push while on `main` or a detached HEAD,
- push to `main` in any form,
- use `--no-verify`, or `--force` without `--with-lease`.

```bash
b=$(git branch --show-current); [[ -z $b || $b == main ]] && echo "STOP: switch to a feature branch"
```

## Start
1. Ask which member is working (list in `AGENTS.md` guardrail 2) and the feature name.
2. Tree must be clean: `git status --porcelain` prints nothing, else commit or stash.
3. Update main: `git fetch origin --prune && git checkout main && git pull --ff-only origin main`. If `--ff-only` fails, someone committed on local `main`: stop and tell the user.
4. Create the branch and check its name:
   ```bash
   b=feat/jered-claim-long-poll
   [[ $b =~ ^feat/[a-z]+-[a-z0-9]+(-[a-z0-9]+)*$ ]] && git checkout -b "$b"
   ```

## Continue
1. `git fetch origin --prune && git checkout <branch>` (only on the remote: `git checkout --track origin/<branch>`).
2. Stash local changes if any, then `git rebase origin/main`.
3. On conflict: keep both intents. Never hand-merge generated files; regenerate them (`python -m app.export_openapi`, `./scripts/sync-contracts.sh`, `./scripts/sync-agents.sh`). Then `git add <file> && git rebase --continue`. If you do not understand the other side, `git rebase --abort` and ask its author (`git log origin/main -- <file>`).
4. Run the gate before writing new code so you know the base is green.

## Finish (before every PR, in order)
1. Rebase again: `git fetch origin --prune && git rebase origin/main`. A gate run before this does not count.
2. Run the repo gate from the "Gates" table in `AGENTS.md`, plus `bash scripts/sync-agents.sh --check`. Keep the output. Red gate: fix, commit, rerun.
3. Adversarial self-review. Spawn 4 subagents in parallel, fresh context each, one lens each, none seeing the others' output:

   | Lens | Looks for |
   |---|---|
   | Correctness | wrong logic, edge cases, races (give the interleaving), tests that do not test the claim |
   | Security / privacy | missing auth or access checks, JWT checks, clinical data in logs, fixtures, errors or outbound requests, secrets |
   | Contracts / compat | OpenAPI and `app/contracts` changes, old clients and rows, Alembic up and down, design rules the change touches |
   | Resources | heavy imports or whole-file reads in the API, unbounded queries, shared GPU memory, unmeasured numbers |

   Prompt each one:
   ```text
   Adversarial reviewer for repo [repo], branch [b], lens [lens]. Run `git diff origin/main...HEAD`,
   read every changed file in full and AGENTS.md. Prove the change is wrong, unsafe or incomplete
   under your lens. No praise. Per finding: P0 (blocks merge) / P1 (must fix) / P2 (note), file:line,
   a concrete failing scenario, a fix. If nothing, list what you tried and why it held. Do not edit files.
   ```
   Fix each finding (then rerun step 2) or answer it in one line. An open P0 blocks the PR. No subagents available: run each lens in a separate fresh session, never in the context that wrote the code.
4. Cascade: update the one home of any fact you changed and grep for stale mentions (`AGENTS.md`, "Cascade"). Also run any repo-specific checks in that repo's `AGENTS.md`.
5. Push: `git push -u origin HEAD`, or after rebasing a pushed branch `git push --force-with-lease origin HEAD`. A 403 means no write access to the repo: ask an org owner for it, do not work around it.
6. Write the PR body to `.git/PR_BODY.md` with a file-writing tool (not a heredoc), then:
   ```bash
   gh pr create --base main --head "$b" --title "worker: claim jobs with long-poll" --body-file .git/PR_BODY.md
   ```
   Title `<area>: <imperative>`, under 70 characters. Body sections:
   ```markdown
   ## What and why
   ## Gate (after rebase on origin/main <short sha>)
   ## Adversarial self-review
   | Lens | Findings | Outcome |
   ## Contract impact
   ## Repo-specific checks (see the repo AGENTS.md)
   ```
   Every section filled; "n/a" needs a reason. Return the PR URL and remind the user another member must review before merge.
