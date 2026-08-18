# Quickstart: RBAC Best Practices for Microsoft Entra ID App Registrations

**Audience:** Identity / Platform teams managing App Registrations at scale
**Scenario addressed:** Applications being removed while users retain elevated permissions or ownership tied to those apps; lack of a governed lifecycle for App Registrations.

> This document is the conceptual guide. For the hands-on version, run the scripts in [`../scripts`](../scripts) (see the repo [README](../README.md)) and read [LESSONS.md](LESSONS.md).

---

## 1. Key concepts (read this first)

Understanding the object model explains *why* permissions linger after an app is "deleted":

| Object | What it is | Where it lives |
|---|---|---|
| **App Registration** (`application`) | The app's definition: identity, credentials, API permissions requested | Home tenant only |
| **Enterprise Application** (`servicePrincipal`) | The local instance of the app in a tenant; holds role assignments, consented permissions, and user assignments | Every tenant where the app is used |
| **Owners** | Users who can manage the app object itself (add credentials, change permissions) — *this is not RBAC*, it is per-object ownership | Both objects, independently |
| **Entra directory roles** | Tenant-wide (or scoped) admin roles such as Application Administrator | Directory |

**The common failure mode:** deleting the App Registration does **not** automatically clean up:

1. The corresponding **service principal** (Enterprise Application) and its consented permissions / OAuth2 grants.
2. **Directory role assignments** (e.g., Application Administrator) that were granted to users so they could manage that app — these are tenant-wide and outlive any single app.
3. **Azure RBAC role assignments** held by the service principal — they become orphaned records ("Identity not found").

So "elevated permissions remaining with users" is expected behavior when broad directory roles are used instead of scoped, just-in-time access. The fix is a combination of **least-privilege role design + PIM + lifecycle governance**, described below.

---

## 2. Role design: who should be able to do what

### 2.1 Stop assigning broad roles permanently

Avoid permanent assignment of these tenant-wide roles:

- **Application Administrator** — manages *all* app registrations and enterprise apps, including adding credentials to any app (a well-known privilege-escalation path).
- **Cloud Application Administrator** — same, minus Application Proxy.

**Instead:**

1. **Application Developer** role for people who only need to *create* their own app registrations (they automatically become owner of what they create, nothing else).
2. **Per-app ownership** for teams that manage a specific app: assign them as owners of *their* App Registration and Enterprise Application only.
3. **PIM (Privileged Identity Management)** for the few people who genuinely need Application Administrator: make the role **eligible**, not active — activated just-in-time, with MFA, justification, approval, and a time limit (e.g., 8 hours).

### 2.2 Restrict who can create app registrations at all

Portal: **Entra ID → Users → User settings → "Users can register applications" → No**

Then grant creation ability deliberately via the **Application Developer** role (ideally as a PIM-eligible assignment to a group).

### 2.3 Use role-assignable groups

Assign roles to **role-assignable security groups** managed through PIM, not to individual users. When someone changes teams, removing them from one group removes all associated elevation — this directly prevents the "permissions stayed with the user" problem.

### 2.4 Restrict user consent

**Entra ID → Enterprise applications → Consent and permissions:**

- Set user consent to **"Allow user consent for apps from verified publishers, for selected permissions"** (or disable entirely).
- Enable the **admin consent workflow** so users can request, and admins approve, higher-privilege permissions.

---

## 3. Lifecycle: removing an application *completely*

The correct decommission order (implemented in [`scripts/06-decommission.sh`](../scripts/06-decommission.sh)):

```
1. Remove RBAC role assignments        (works by principalId even for orphans)
2. Revoke OAuth2 grants / app role assignments
3. Delete the service principal
4. Delete the app registration
5. Purge from soft-delete (30-day window) after validation
6. Review directory roles granted to HUMANS because of this app
```

Step 6 is the one that closes the gap most organizations hit:

- Was anyone granted **Application Administrator / Cloud Application Administrator** *because of* this app? If the role is no longer justified by another app, remove the assignment (or the group membership).
- Remove the decommissioned app's team from any **role-assignable group** if their elevation is no longer needed.

For the PowerShell (Microsoft Graph SDK) equivalent of each step, both approaches work — this repo standardizes on **Azure CLI + `az rest`** so everything runs in Cloud Shell with no module installs.

---

## 4. Custom Azure roles for subscription lifecycle (cancellation)

A recurring ask, told here as **Contoso**: a small operations group needs to **cancel subscriptions** without holding Owner or Contributor. The right answer is a **custom role**, and it raises two questions worth getting exactly right:

### 4.1 The minimal action set

```json
{
  "Actions": [
    "Microsoft.Resources/subscriptions/read",
    "Microsoft.Subscription/cancel"
  ],
  "NotActions": [],
  "AssignableScopes": ["/subscriptions/<sub-id>"]
}
```

- **`Microsoft.Subscription/cancel`** is the action that authorizes cancellation.
- **`Microsoft.Resources/subscriptions/read`** is required for the subscription to be **visible in the Azure portal** (and in `az account list`) for the assignee. Without it, the user cannot even navigate to the subscription to cancel it, so the workflow silently breaks. This is not privilege creep: `read` on the subscription exposes metadata, not resource contents.
- **`AssignableScopes`** pins where the role can be assigned. Prefer listing the specific subscriptions (or a management group that contains only the subscriptions in scope) over the tenant root.

### 4.2 How to validate without destroying anything

Never test by cancelling a real subscription. Safe validation, in order:

1. `az role definition list --name <role>` — confirm the effective actions.
2. `az role assignment list --assignee <principal> --scope /subscriptions/<id>` — confirm the assignment exists at the right scope.
3. Log in as the assignee and run `az account list` — the subscription appears only when the `read` action is present. Remove the action, update the role, and it disappears: that demonstrates the portal-visibility requirement.

Hands-on version: [`scripts/07-custom-role-subscription.sh`](../scripts/07-custom-role-subscription.sh).

### 4.3 Decommissioning the subscription itself (the reverse problem)

The orphan problem also runs in the opposite direction. When a subscription that appears in custom role `AssignableScopes` is cancelled/deleted:

- Removing that subscription from the role's `AssignableScopes` fails with **`RoleScopeBeingRemovedContainsAssignments`** while role assignments still exist at that scope — even when PowerShell/CLI no longer *show* those assignments, because backend references can outlive the subscription.
- With the subscription gone, you can no longer enumerate or delete those assignments yourself. At that point the only fix is a **Microsoft support case** so the Product Group cleans up the orphaned backend references. Multiply this by every custom role that listed the subscription (real cases have hit 40+ roles at once).

**Prevention — subscription decommission order, before cancelling/deleting:**

```
1. Delete all role assignments at the subscription scope
   az role assignment list --scope /subscriptions/<id> --include-inherited false
   az role assignment delete --ids <...>
2. Remove the subscription from AssignableScopes of every custom role that lists it
   (script 05, section 4, finds these)
3. Only then cancel/delete the subscription
```

This mirrors the app rule in Section 3: **the scope's death is the LAST step, never the first.**

### 4.4 Governance notes for custom roles

- Assign the role to a **role-assignable group** (ideally PIM-eligible), not to individuals, consistent with Section 2.3.
- Custom roles count against a **limit of 5,000 per tenant** — consolidate instead of creating near-duplicates.
- Keep `AssignableScopes` short and current: every subscription listed is one more place that must be cleaned before that subscription can ever be decommissioned (see 4.3).
- Review custom roles in the same quarterly access review cycle as privileged directory roles.

---

## 5. Ongoing governance (prevent recurrence)

**Access Reviews (Entra ID Governance):** create quarterly reviews for (a) privileged directory roles and (b) owners/users assigned to critical enterprise apps. Unreviewed access can be auto-removed.

**PIM alerts:** enable alerts such as "roles are being assigned outside of PIM" and "there are too many global administrators."

**Credential hygiene:**

- Prefer **managed identities** (for Azure-hosted workloads) and **workload identity federation** (for GitHub Actions, external workloads) over client secrets.
- Where secrets are unavoidable, use **app management policies** to enforce maximum secret lifetimes and block long-lived credentials.

**Detect orphaned / stale apps:** run [`scripts/05-audit-orphans.sh`](../scripts/05-audit-orphans.sh) on a schedule — it finds orphaned role assignments, soft-deleted apps, expired credentials, and ownerless apps. Also review **Entra ID → Monitoring & health → Recommendations**, which flags unused applications, unused credentials, and apps using legacy permissions.

---

## 6. Quick checklist

- [ ] "Users can register applications" set to **No**
- [ ] Application Developer role used for self-service creation (via PIM-eligible group)
- [ ] Application Administrator / Cloud Application Administrator: **eligible via PIM only**, assigned to role-assignable groups, with approval + MFA + max duration
- [ ] Per-app access managed through **ownership**, max 2–3 owners per app, no orphaned apps
- [ ] User consent restricted; admin consent workflow enabled
- [ ] Decommission runbook (Section 3 / script 06) adopted — role assignments, grants, and service principal removed together with the app
- [ ] Subscription cancellation (and similar sensitive operations) handled via **custom roles** with the minimal action set, pinned `AssignableScopes`, assigned to PIM-eligible groups (Section 4)
- [ ] Quarterly access reviews on privileged roles and critical app assignments
- [ ] Secrets replaced by managed identities / federated credentials where possible; app management policies enforcing credential lifetimes
- [ ] Monitoring: audit logs streamed to SIEM, Entra recommendations reviewed monthly, audit script (05) scheduled

---

## References

- Microsoft Learn: *Best practices for Microsoft Entra roles* — least privilege and PIM guidance
- Microsoft Learn: *Grant tenant-wide admin consent / Configure user consent settings*
- Microsoft Learn: *Delete and restore applications* (soft-delete behavior)
- Azure CLI reference: `az ad app`, `az ad sp`, `az role assignment`, `az rest`
