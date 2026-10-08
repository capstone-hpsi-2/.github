---
name: pr-review
description: Understand or review someone else's pull request in admin-backend, transcription-backend or frontend. Produces P0/P1/P2 findings anchored to file:line, checked against the design it implements, with the repo gate actually run. Use for "review PR #N", "what does this PR do", "is this safe to merge". Not for your own branch (that is the self-review in feature-branch).
---

# PR review

Two uses, one method:
- **Understand a PR**: lead with "What this PR does" and your open question.
- **Review before merge**: lead with the verdict.

## Discipline
1. Every claim anchored to `file:line`. If something is not built yet, say so.
2. Go beyond the ask: flag bugs found in passing and files the author forgot (regenerated `openapi.yaml`, a migration, docs the repo `AGENTS.md` requires).
3. Backward compatibility: say what old callers, old rows and an old cached PWA do.
4. Honest about the unknown. An unmeasured number is an open question, not a fact.
5. Three or more parallel items go in a table.

## Get the PR
```bash
gh pr view 42 --json number,title,author,headRefName,body,files,additions,deletions
gh pr checkout 42                          # read-only: never push to the author's branch
git fetch origin && git merge-base HEAD origin/main
git diff --stat origin/main...HEAD
```
Post to GitHub only when the user asks: `gh pr review 42 --comment --body-file review.md`.

## Before writing
- Read the repo's `AGENTS.md`, especially `## <repo> specifics`: some odd-looking things are deliberate.
- Run the gate from the "Gates" table in `AGENTS.md` and report real counts from the output.
- Check the PR body's self-review table: each "fixed" is in the diff, each "answered" holds. A missing table is a P1.

## Project risks (each a P0 candidate; commands in reference.md)

| Area | Failure to look for |
|---|---|
| Clinical data | content in logs, errors, fixtures, or any request leaving our servers |
| Auth | route without an auth dependency; JWT checks weaker than admin-backend `app/modules/auth_rbac/tokens.py`; worker token and user JWT interchangeable |
| Access | a read that skips the access rule in `DESIGN.md` Security |
| Case-note lifecycle | a path that bypasses a rule in `DESIGN.md` Case-note lifecycle |
| Data layout | a table outside the layout in `DESIGN.md` Data; one repo migrating the other's schema |
| Contracts | route or schema change without regenerated `openapi/openapi.yaml` |
| Resources | model or torch import in the API; whole-file audio reads; unmeasured performance numbers |

Method, report structure and finding template: [reference.md](reference.md). Read it before writing.
