# Lessons — what this lab demonstrates

## 1. App Registration ≠ Service Principal

Script `01` creates two objects. The **application object** is the definition; the **service principal** is the identity that actually receives RBAC and consents. Deleting one without governing the other is the root of most cleanup problems.

## 2. RBAC is granted to the SP, at the narrowest scope, with the narrowest role

Script `02` assigns `Storage Blob Data Reader` at resource-group scope. In production, prefer the resource scope itself when practical. Never default to `Contributor` "to make it work".

## 3. Testing least privilege means testing denials too

Script `03` runs a **positive test** (read works) and a **negative test** (write fails). If the negative test passes (i.e., write succeeds), the role is too broad — treat it as a failed test.

## 4. Orphaned assignments: the customer's exact symptom

Script `04` deletes the app without removing the role assignment. The assignment survives with `principalName` empty (portal shows *"Identity not found"*, type *Unknown*). Consequences in real tenants:

- Noise and risk in access reviews (nobody knows what the assignment was for)
- If the app is **restored from soft-delete**, the old permission silently comes back to life
- Role-assignment quota (up to 4,000 per subscription) gets consumed by garbage

## 5. Correct decommission order

```
role assignments → OAuth2 grants / app role assignments → service principal → app registration → purge soft-delete → review human directory roles
```

Script `06` implements this and is idempotent: it also fixes the situation when someone already deleted the app the wrong way.

## 6. The humans are part of the cleanup

The most common "elevated permissions remaining with users" case is not RBAC at all — it's people keeping **Application Administrator / Cloud Application Administrator** after the app that justified the role is gone. Mitigations:

- Make these roles **PIM-eligible only** (no permanent assignments), activated with MFA + justification + time limit
- Assign roles via **role-assignable groups**; removing someone from the team removes the elevation
- Quarterly **access reviews** on privileged roles with auto-removal of unreviewed access

## 7. Credentials

The lab uses a client secret with a 24-hour lifetime for simplicity. In production:

- Azure-hosted workloads → **managed identity** (no credentials at all)
- GitHub Actions / external → **workload identity federation**
- If secrets are unavoidable → enforce max lifetime via **app management policies**, and monitor expiry (script `05`, section 3)

## 8. Custom roles: least privilege for sensitive operations (subscription cancellation)

Script `07` models the follow-up from the customer's May 12 session: a custom role that allows **cancelling a subscription** without Owner/Contributor.

- `Microsoft.Subscription/cancel` authorizes the cancellation itself.
- `Microsoft.Resources/subscriptions/read` is what makes the subscription **visible in the portal** for the assignee — without it the workflow silently breaks, because the user cannot navigate to what they cannot read. Requiring `read` is not privilege creep; it exposes metadata only.
- `AssignableScopes` pins where the role can be assigned.
- Validation is done **without ever invoking the cancel action**: check the definition, check the assignment, and prove portal visibility by toggling the `read` action.

The same lesson applies to the subscription as a scope. A real support case pattern: a subscription is deleted while custom roles still list it in `AssignableScopes` and role assignments still exist at that scope. Updating the roles then fails with `RoleScopeBeingRemovedContainsAssignments`, the assignments are no longer visible to CLI/PowerShell, and only a Microsoft support case (Product Group backend cleanup) can unblock it — across every affected role. Prevention is the decommission order in QUICKSTART §4.3: assignments → AssignableScopes → then the subscription. **The scope's death is the last step, never the first.** Script `05` section 4 detects roles whose `AssignableScopes` reference subscriptions that are no longer visible.

## 9. Make the audit continuous

Script `05` is intentionally standalone so it can be scheduled (cron, Azure Automation, GitHub Actions with OIDC) against a real tenant: orphaned assignments, soft-deleted apps, expired credentials, ownerless apps.
