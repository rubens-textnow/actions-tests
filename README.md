# actions-tests

Minimal repro of textnow-server's hotfix-fast-path merge-queue pipeline. Used to debug why
`trigger-prod-canary-deploy` (in the real repo) gets instant-skipped with zero sub-jobs
when `is_hotfix=true`, even after multiple attempted fixes.

## Pipeline structure

Mirrors `textnow-server/.github/workflows/` as closely as possible:

| File                                          | Mirrors                       | Purpose                                       |
|-----------------------------------------------|-------------------------------|-----------------------------------------------|
| `.github/workflows/mq.yaml`                   | `mq.yaml`                     | Main orchestrator (`merge_group` event)       |
| `.github/workflows/auto-deploy.yaml`          | `mq-auto-deploy.yaml`         | Reusable, no environment gate (used by stage) |
| `.github/workflows/manual-deploy.yaml`        | `mq-manual-deploy.yaml`       | Reusable, conditional environment             |
| `.github/scripts/resolve-stage-runtime.sh`    | same name                     | Hotfix detection from PR label / branch       |

The three deploy stages in `mq.yaml`:

| Stage  | Reusable workflow      | Environment lookup                                              | Hotfix behavior              |
|--------|------------------------|-----------------------------------------------------------------|------------------------------|
| stage  | `auto-deploy.yaml`     | none                                                            | always auto (no change)      |
| canary | `manual-deploy.yaml`   | `canary` (normal) or `auto-deploy` (hotfix)                     | routes to `auto-deploy` env  |
| prod   | `manual-deploy.yaml`   | `prod` (always — `is_hotfix` not wired AND self-protected)      | NEVER auto-deploys           |

The conditional environment expression in `manual-deploy.yaml`:

```yaml
environment: ${{ inputs.is_hotfix && inputs.target_env != 'prod' && 'auto-deploy' || inputs.target_env }}
```

## One-time repo setup

1. **Create three environments** in **Settings → Environments**:
   - `canary` — set at least one required reviewer
   - `prod` — set at least one required reviewer
   - `auto-deploy` — no required reviewers, no wait timer
2. **Create the `hotfix-fast-path` label** in **Issues → Labels**.
3. **Enable the merge queue** in **Settings → Branches → Branch protection rule for `main`**:
   - Require status checks: add `merge-queue-gate-checklist`
   - Require merge queue: ✅
4. **Allow GitHub Actions to read PRs** (Settings → Actions → General → Workflow permissions → Read repository contents and pull request permissions).

## How to test

### Normal path (expected: canary and prod both block on manual approval)

1. Branch: `test/normal-flow`. Bump `marker.txt`. Open a PR.
2. Click **Merge when ready** in the PR.
3. Expected pipeline:
   - `resolve-stage-runtime` → `is_hotfix=false`
   - `trigger-stage-deploy` → succeeds immediately
   - `trigger-canary-deploy / trigger-deployment` → **Waiting for canary approval**
   - After approving canary → `trigger-canary-deploy / check-and-deploy` → success
   - `trigger-prod-deploy / trigger-deployment` → **Waiting for prod approval**
   - After approving prod → all green

### Hotfix path (expected: canary skips approval, prod still blocks)

1. Branch: `hotfix/test-fast-path` (the `hotfix-` prefix alone triggers the script) OR any branch + the `hotfix-fast-path` label on the PR. Bump `marker.txt`. Open the PR.
2. Click **Merge when ready**.
3. Expected pipeline:
   - `resolve-stage-runtime` → `is_hotfix=true`
   - `trigger-stage-deploy` → succeeds immediately
   - `trigger-canary-deploy / trigger-deployment` → **runs against `auto-deploy` env, no approval**
   - `trigger-canary-deploy / check-and-deploy` → success
   - `trigger-prod-deploy / trigger-deployment` → **Waiting for prod approval** (NOT skipped)
   - After approving prod → all green

### Failure mode we're reproducing

In `textnow-server`, when the hotfix path runs, `trigger-prod-canary-deploy` (the equivalent of
`trigger-canary-deploy` here) is reported as `skipped` with `started_at == completed_at` and zero
sub-jobs. None of `trigger-deployment` / `check-and-deploy` are scheduled. The cascade then skips
prod and everything downstream.

If we can reproduce that here, we can isolate whether the cause is:
- the conditional environment expression itself,
- the `auto-deploy` env missing (today's environments list in textnow-server does not include it),
- a `merge_group` + nested-reusable-workflow scheduling quirk,
- or something else entirely.
