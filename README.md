# App Registration RBAC Lifecycle Lab

Hands-on lab that walks through the **full lifecycle of an App Registration**: create → grant RBAC → test → decommission → verify cleanup. It also **deliberately reproduces the "orphaned permission" problem** (permissions remaining after an app is removed) and shows how to detect and fix it.

Everything runs with **Azure CLI + bash** — works locally (Linux/macOS/WSL) or in **Azure Cloud Shell** with zero setup.

## Start here

1. **[docs/QUICKSTART.md](docs/QUICKSTART.md)** — the conceptual guide: object model (App Registration vs Service Principal), RBAC role design, PIM, consent, and the governance checklist. Read this first.
2. **This README** — how to run the hands-on lab.
3. **[docs/LESSONS.md](docs/LESSONS.md)** — what each script demonstrates, mapped to production guidance.

## Why this lab exists

Deleting an App Registration does **not** automatically clean up:

- The **service principal** (Enterprise Application) and its consented permissions
- **Azure RBAC role assignments** — they become *orphaned* ("Identity not found / Unknown" in the portal)
- **Entra directory roles** granted to humans so they could manage that app

This lab makes that failure mode visible in a sandbox, then teaches the correct decommission order.

## Prerequisites

- Azure CLI ≥ 2.60 (`az version`)
- Logged in: `az login`
- Permissions: ability to create app registrations (Application Developer or higher) and `Owner`/`User Access Administrator` on the target subscription (needed to create role assignments)
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
│   ├── 05-audit-orphans.sh      # detect orphaned role assignments + stale credentials
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

# Path A — reproduce the customer's problem:
./scripts/04-simulate-problem.sh
./scripts/05-audit-orphans.sh      # shows the orphaned assignment
./scripts/06-decommission.sh       # cleans up the orphan + soft-deleted app

# Path B — do it right the first time:
# skip 04 and run 06 directly after 03

# Path C — custom role for subscription cancellation (customer follow-up):
./scripts/07-custom-role-subscription.sh            # never cancels anything — safe validation only
./scripts/07-custom-role-subscription.sh --cleanup  # remove the role + assignment

./scripts/99-cleanup.sh
```

Each script prints what it's doing and writes state (object IDs) to `.lab-state` so the next script can pick it up. Nothing sensitive is committed: `.env`, `.lab-state` and any secret material are gitignored.

## The one rule to remember

> **Decommission order matters:** remove role assignments and revoke grants **before** deleting the service principal, and delete the service principal **before** (or together with) the app registration. Then purge the soft-deleted object and review any directory roles that were granted to humans because of this app.
