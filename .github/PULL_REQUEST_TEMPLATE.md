## What & why

<!-- One or two sentences. Link the issue: Closes #123 -->

## Contract impact

- [ ] None
- [ ] **REST/WS contract changed**: `openapi/openapi.yaml` regenerated and committed (`python -m app.export_openapi`)
- [ ] **Breaking** for a consumer: the frontend PR bumping `contracts.lock.json` is linked here
- [ ] **Env** name added/changed: `admin-backend/deploy/.env.example` updated (canonical list)
- [ ] **Auth/JWT claims** changed: both backends updated and smoke test passes

## Security checklist (if touching routes, auth, realtime, or caching)

- [ ] New routes are RBAC-guarded server-side (`x-required-roles` present)
- [ ] New WS channels are added to the channel policy (checked on subscribe)
- [ ] No API responses newly cached by the service worker
- [ ] No secrets, tokens, or personal data in logs

## How it was tested

<!-- Commands run, screenshots for UI changes. "smoke-test.sh --local passed" for anything cross-repo. -->
