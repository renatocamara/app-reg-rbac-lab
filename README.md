# App Registration RBAC Lifecycle Lab

Hands-on lab about a single failure family in Azure RBAC: **references that outlive the thing they point to.**

It happens in two directions:

| Direction | What dies | What survives | Symptom |
|---|---|---|---|
| **Identity deleted** | App Registration / Service Principal | Its role assignments | Orphaned assignments: *"Identity not found"*, type *Unknown*; permissions silently revive if the app is restored from soft-delete |
| **Scope deleted** | Subscription | Role assignments at that scope + `AssignableScopes` references in custom roles | Custom role updates blocked by `RoleScopeBeingRemovedContainsAssignments`; assignments invisible to CLI/PowerShell but still enforced by the backend; only a Microsoft support case (Product Group backend cleanup) can unblock it |

Both are the same mistake at different levels: **the deletion happened before the cleanup.** This lab reproduces the first direction end to end in a sandbox, teaches the decommission order that prevents both, and ships an audit script that detects both in a real tenant.

Everything runs with **Azure CLI + bash** — works locally (Linux/macOS/WSL) or in **Azure Cloud Shell** with zero setup.

## Start here

1. **[docs/QUICKSTART.md](docs/QUICKSTART.md)** — the conceptual guide: object model (App Registration vs Service Principal), RBAC role design, PIM, consent, custom roles for sensitive operations (subscription cancellation), subscription decommissioning, and the governance checklist. Read this first.
2. **This README** — how to run the hands-on lab.
3. **[docs/LESSONS.md](docs/LESSONS.md)** — what each script demonstrates, mapped to production guidance.

## What the lab covers

**1. App Registration lifecycle (scripts 00-06).** Create → grant least-privilege RBAC → test both directions (access works, excess is denied) → then deliberately delete the app the *wrong* way to produce an orphaned role assignment, detect it, and fix it with the correct decommission runbook.

**2. Custom roles for sensitive operations (script 07).** Modeled on a real ask, told here as **Contoso**: cancel a subscription without holding Owner/Contributor. Builds the minimal-action custom role (`Microsoft.Subscription/cancel` + `Microsoft.Resources/subscriptions/read`), explains why the `read` action is required for the subscription to even appear in the portal, and validates everything **without ever invoking the cancel action**.

**3. Stale scope detection (script 05, section 4).** Modeled on a real support case (also as Contoso): a subscription was deleted while dozens of custom roles still listed it in `AssignableScopes` and assignments still existed at that scope. Result: every role update blocked, no self-service fix possible. The audit finds custom roles pointing at subscriptions that no longer exist — *before* it becomes a support case.

## Prerequisites

- Azure CLI ≥ 2.60 (`az version`)
- Logged in: `az login`
- Permissions: ability to create app registrations (Application Developer or higher) and `Owner`/`User Access Administrator` on the target subscription (needed to create role assignments and custom roles)
- `jq` installed (pre-installed in Cloud Shell)

## Repo layout

```
.
├── README.md
├── .env.example          # copy to .env and adjust — .env is gitignored
├── .gitattributes        # forces LF on shell scripts (Windows-friendly repo)
├── .gitignore
├── scripts/
│   ├── 00-setup-infra.sh        # resource group + storage account (test target)
│   ├── 01-create-app.sh         # app registration + service principal + secret
│   ├── 02-grant-rbac.sh         # least-privilege role assignment at RG scope
│   ├── 03-test-access.sh        # login as the SP and prove access works (and denied outside scope)
│   ├── 04-simulate-problem.sh   # ⚠ delete the app the WRONG way → orphaned assignment
│   ├── 05-audit-orphans.sh      # detect orphaned assignments, stale credentials, stale AssignableScopes
│   ├── 06-decommission.sh       # the CORRECT decommission runbook
│   ├── 07-custom-role-subscription.sh  # custom role for subscription cancellation (least privilege + portal visibility)
│   └── 99-cleanup.sh            # tear down lab infra
└── docs/
    ├── QUICKSTART.md            # conceptual guide: RBAC best practices for App Registrations
    └── LESSONS.md               # what the lab demonstrates, mapped to real-world guidance
```

## How to run

```bash
cp .env.example .env   # edit values if you want
source .env

./scripts/00-setup-infra.sh
./scripts/01-create-app.sh
./scripts/02-grant-rbac.sh
./scripts/03-test-access.sh

# Path A — reproduce the orphaned-permission problem:
./scripts/04-simulate-problem.sh
./scripts/05-audit-orphans.sh      # shows the orphaned assignment
./scripts/06-decommission.sh       # cleans up the orphan + soft-deleted app

# Path B — do it right the first time:
# skip 04 and run 06 directly after 03

# Path C — custom role for subscription cancellation:
./scripts/07-custom-role-subscription.sh            # never cancels anything — safe validation only
./scripts/07-custom-role-subscription.sh --cleanup  # remove the role + assignment

./scripts/99-cleanup.sh
```

Each script prints what it's doing and writes state (object IDs) to `.lab-state` so the next script can pick it up. Nothing sensitive is committed: `.env`, `.lab-state` and any secret material are gitignored.

The audit script (`05`) is intentionally standalone: point it at a real tenant and schedule it (cron, Azure Automation, GitHub Actions with OIDC).

## The one rule to remember

> **The deletion is the LAST step, never the first.** For an app: remove role assignments and revoke grants before deleting the service principal, delete the service principal before the app registration, then purge the soft-delete and review the human directory roles. For a subscription: delete the role assignments at its scope and remove it from every custom role's `AssignableScopes` before cancelling it. Skip the order and the leftovers can only be removed by Microsoft support.
