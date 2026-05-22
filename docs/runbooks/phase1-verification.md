# Phase 1 — Resources Created & Console Verification

Everything built in Phase 1, how to find each resource in the GCP Console,
how to verify it via CLI, and what key terms mean.

---

## Key Terms

### Resource Hierarchy
GCP organises everything in a strict tree:

```
Organisation (meelass.com)
└── Folder  (e.g. prod, nonprod, security …)
    └── Project  (e.g. networking-host-prod)
        └── Resource  (VM, GCS bucket, Cloud SQL instance …)
```

**Why it matters:** IAM permissions and org policies set at a higher level
automatically *inherit* downward. A policy enforced on the organisation applies
to every folder, project, and resource underneath it — without touching each one
individually. A policy enforced on the `prod` folder applies to every project
inside `prod`.

---

### Org Policy
A rule enforced by GCP's Resource Manager that restricts what can be done
inside an organisation, folder, or project — regardless of what IAM permissions
a user has.

- **Boolean policy** — a constraint that is either ON (enforced) or OFF. Example:
  `compute.requireShieldedVm = ON` means you cannot create a VM without Shielded
  VM enabled, full stop.
- **List policy** — a constraint that specifies an allow-list or deny-list of
  values. Example: `compute.vmExternalIpAccess = DENY ALL` means no VM anywhere
  in the org can be given an external IP.
- **Inheritance** — a policy set at the org level propagates down to all folders
  and all projects. A folder or project can override it (stricter or looser)
  unless the org policy itself is marked as not-overridable.

---

### Audit Log Types
GCP has three categories of audit log, each capturing different activity:

| Log type | What it records | Example entry |
|---|---|---|
| **Admin Activity** (`ADMIN_READ`) | Changes to configuration or metadata — creating resources, modifying IAM policies, enabling APIs | "User X created a VM named Y" |
| **Data Read** (`DATA_READ`) | Reading the *contents* of data — listing GCS objects, reading BigQuery rows, reading a Secret Manager secret | "User X read secret projects/p/secrets/db-password" |
| **Data Write** (`DATA_WRITE`) | Writing or modifying data — uploading a file to GCS, inserting BigQuery rows | "Service account X wrote object gs://bucket/file.csv" |

Admin Activity logs are always on (cannot be disabled).
Data Read and Data Write are off by default and must be explicitly enabled —
which is what Phase 1 did for `allServices` at org level.

---

### Terraform State
When Terraform creates a resource (a folder, a VM, a firewall rule), it writes
a record of that resource into a **state file** stored in the GCS bucket
`meelass-terraform-state-4740a462`. Each platform layer has its own state file
at a different path (prefix) inside that bucket.

The state file is what allows Terraform to know on the next run what already
exists, what needs to change, and what should be destroyed. It is the source of
truth for "what Terraform manages".

---

### Billing Budget vs. Billing Alert
- **Budget** — a defined spending ceiling (e.g. CAD $100/month) against which
  GCP tracks your actual spend.
- **Threshold rule** — a percentage of that ceiling that triggers a notification
  (e.g. 10% = CAD $10, 50% = CAD $50). Thresholds send emails; they do
  **not** stop spending or kill resources. GCP does not automatically stop
  resources when a budget is exceeded — you are responsible for acting on the
  alert.
- **Credit types treatment** — whether promotional credits (free trial credit,
  sustained-use discounts, committed-use discounts) are counted toward your
  spend or excluded. `INCLUDE_ALL_CREDITS` means credits reduce your measured
  spend, so the alert fires later.

---

## Resources Created in Phase 1

### 1 — Folder Hierarchy

Six top-level folders under `organisations/473689265669`:

| Folder name | Folder ID | Purpose |
|---|---|---|
| `infrastructure` | `386767465346` | VPCs, subnets, DNS, NAT, interconnects |
| `security` | `509957683122` | KMS, SCC, audit sinks, policy enforcement |
| `shared-services` | `667624449165` | CI/CD, Artifact Registry, monitoring |
| `prod` | `442721992513` | Production workload projects |
| `nonprod` | `373396933001` | Staging, dev, QA workload projects |
| `sandbox` | `323037062130` | Developer experimentation — relaxed policies |

**Terraform source:** `terraform/platform/folders/`
**State file:** `gs://meelass-terraform-state-4740a462/platform/folders/default.tfstate`

#### Verify in Console

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Click the **project selector** at the top → click the **ALL** tab → click
   `meelass.com` (the Organisation row, not a project)
3. Hamburger menu (≡) → **IAM & Admin** → **Manage resources**
4. You will see `meelass.com` as the root with all 6 folders listed directly
   underneath it
5. Click any folder — you will see it is empty (no projects yet; those arrive
   in Phase 5)

#### Verify via CLI

```bash
gcloud resource-manager folders list \
  --organization=473689265669 \
  --impersonate-service-account=terraform-org-admin@meelass-terraform-admin.iam.gserviceaccount.com
```

Expected output: 6 rows, one per folder, each showing its numeric ID and
display name.

---

### 2 — Organisation Policies

Ten constraints enforced at the `organisations/473689265669` level. Because
they are set at the org root, they apply to every folder, project, and resource
in `meelass.com` automatically — including all 6 folders just created.

Full explanation of every policy: `docs/architecture/org-policies-reference.md`

| Constraint | Type | Effect |
|---|---|---|
| `compute.requireShieldedVm` | Boolean | Every VM must have Secure Boot + vTPM + Integrity Monitoring |
| `compute.requireOsLogin` | Boolean | SSH via IAM only — no static metadata SSH keys |
| `compute.skipDefaultNetworkCreation` | Boolean | New projects start with no VPC |
| `compute.vmExternalIpAccess` | List — deny all | No VM can have a public IP |
| `iam.disableServiceAccountKeyCreation` | Boolean | No downloadable SA JSON/P12 keys |
| `iam.disableServiceAccountKeyUpload` | Boolean | No uploading your own key to an SA |
| `iam.automaticIamGrantsForDefaultServiceAccounts` | Boolean | Default SAs not auto-granted Editor |
| `storage.uniformBucketLevelAccess` | Boolean | GCS buckets: IAM only, no per-object ACLs |
| `storage.publicAccessPrevention` | Boolean | GCS buckets cannot be made public |
| `gcp.resourceLocations` | List — allow | Resources only in `us-central1` or `global` scope |

**Terraform source:** `terraform/platform/org-policies/`
**State file:** `gs://meelass-terraform-state-4740a462/platform/org-policies/default.tfstate`

#### Verify in Console

1. Switch to `meelass.com` org scope (project selector → ALL → `meelass.com`)
2. Hamburger menu (≡) → **IAM & Admin** → **Organization policies**
3. A table loads with all constraints. Use the **Filter** box to search by name.
4. For each policy above, the **Enforcement** column should show:
   - **Boolean policies** → `Enforced`
   - `compute.vmExternalIpAccess` → the value column shows `Deny: All`
   - `gcp.resourceLocations` → value column shows `Allow: in:us-central1-locations, global`
5. The **Inherited from** column should show `meelass.com` (confirming it came
   from the org root, not a project)
6. Click any policy row to see the full rule detail panel on the right

> **Filter shortcuts:** type `shielded`, `oslogin`, `keyCreation`, `external`,
> `locations`, `public`, `uniform`, `automatic` to find each quickly.

#### Verify via CLI

```bash
# List all org-level policies
gcloud org-policies list \
  --organization=473689265669 \
  --impersonate-service-account=terraform-org-admin@meelass-terraform-admin.iam.gserviceaccount.com

# Inspect one policy in full detail
gcloud org-policies describe compute.requireShieldedVm \
  --organization=473689265669 \
  --impersonate-service-account=terraform-org-admin@meelass-terraform-admin.iam.gserviceaccount.com
```

---

### 3 — Org-wide Audit Logging

All three audit log types — Admin Activity, Data Read, and Data Write — enabled
for **all GCP services** at the organisation level.

**Terraform source:** `terraform/platform/audit-logging/`
**State file:** `gs://meelass-terraform-state-4740a462/platform/audit-logging/default.tfstate`

#### Why the Console view is confusing

The Console page at **IAM & Admin → Audit logs** shows a table of individual
GCP services (Cloud Storage, Compute Engine, BigQuery, etc.). There is **no
visible row labelled "All services"** in this table. This is a UI limitation.

What the `allServices` configuration actually means is: every service in that
table inherits the org-level setting. If you click on any individual service
row (e.g. Cloud Storage), you will see all three log type checkboxes ticked —
that is the inherited `allServices` config showing through.

#### The reliable way to verify

**CLI — direct IAM policy read (most authoritative):**

```bash
gcloud organizations get-iam-policy 473689265669 \
  --impersonate-service-account=terraform-org-admin@meelass-terraform-admin.iam.gserviceaccount.com \
  --format=json \
| python3 -c "
import json, sys
p = json.load(sys.stdin)
for c in p.get('auditConfigs', []):
    print('service:', c['service'])
    for l in c.get('auditLogConfigs', []):
        print(' ', l['logType'])
"
```

Expected output:
```
service: allServices
  DATA_WRITE
  DATA_READ
  ADMIN_READ
```

**Console — verify logs are actually flowing:**

Once any admin action has happened (Terraform runs count), you can confirm
end-to-end in Logs Explorer:

1. Hamburger menu (≡) → **Logging** → **Logs Explorer**
2. Make sure the scope at the top reads `meelass.com` (the org), not a project
3. Paste this filter in the query box and click **Run query**:
   ```
   logName="organizations/473689265669/logs/cloudaudit.googleapis.com%2Factivity"
   ```
4. You should see log entries from the Terraform runs — folder creation, policy
   changes, IAM updates. Each entry shows who did what and when.

**What each log stream looks like:**

| Log name | Contains |
|---|---|
| `cloudaudit.googleapis.com/activity` | Admin Activity — config and IAM changes |
| `cloudaudit.googleapis.com/data_access` | Data Read + Data Write — data access events |
| `cloudaudit.googleapis.com/system_event` | GCP-initiated events (auto-scaling, maintenance) |

---

### 4 — Billing Budget

A monthly budget covering all projects on billing account `01DA3A-863E5F-D24BB4`
with four escalating email alerts.

| Threshold | Amount (CAD) | Basis |
|---|---|---|
| 10% | ~$10 | Current spend this month |
| 25% | ~$25 | Current spend this month |
| 50% | ~$50 | Current spend this month |
| 100% | $100 | Current spend this month |

> **Currency:** This billing account is registered in Canada and uses CAD.
> All budget amounts are in Canadian dollars.

> **Alerts do not stop spending.** When a threshold is crossed, GCP emails
> the billing account admins (`admin@meelass.com`). No resources are paused or
> destroyed. You must act manually if you want to stop spending.

**Terraform source:** `terraform/platform/billing-alerts/`
**State file:** `gs://meelass-terraform-state-4740a462/platform/billing-alerts/default.tfstate`

#### Verify in Console

1. Hamburger menu (≡) → **Billing**
2. In the left sidebar click **Budgets & alerts**
3. You should see one budget: **"Platform Lab Monthly Org Budget"**
4. Click it to see the detail view:
   - **Scope:** All projects on this billing account
   - **Budget amount:** CAD $100.00
   - **Credit types treatment:** Include all credits
   - **Threshold rules:** four rows at 10%, 25%, 50%, 100% — all set to
     "Current spend"
   - **Manage notifications:** Default recipients (billing admins)

#### Verify via CLI

```bash
gcloud billing budgets list \
  --billing-account=01DA3A-863E5F-D24BB4 \
  --billing-project=meelass-terraform-admin \
  --impersonate-service-account=terraform-org-admin@meelass-terraform-admin.iam.gserviceaccount.com
```

---

### 5 — Terraform State Files (bonus verification)

Every platform layer writes its state to a separate path in the GCS bucket.
You can verify all four state files exist:

#### Verify in Console

1. Hamburger menu (≡) → **Cloud Storage** → **Buckets**
2. Click `meelass-terraform-state-4740a462`
3. Navigate into the `platform/` folder — you should see four subfolders:
   `folders/`, `org-policies/`, `audit-logging/`, `billing-alerts/`
4. Inside each one: `default.tfstate` — this is the JSON file Terraform uses
   to track every resource it manages in that layer
5. The file size will be a few KB. Click one and view it — you will see
   the `resources` array listing every GCP resource Terraform knows about

#### Verify via CLI

```bash
gsutil ls -r gs://meelass-terraform-state-4740a462/platform/ \
  --impersonate-service-account=terraform-org-admin@meelass-terraform-admin.iam.gserviceaccount.com
```

Expected output:
```
gs://meelass-terraform-state-4740a462/platform/audit-logging/default.tfstate
gs://meelass-terraform-state-4740a462/platform/billing-alerts/default.tfstate
gs://meelass-terraform-state-4740a462/platform/folders/default.tfstate
gs://meelass-terraform-state-4740a462/platform/org-policies/default.tfstate
```

---

## Phase 1 Post-Bootstrap IAM Fix

During Phase 1 we discovered that `roles/billing.admin` granted at the
**organisation level** does not give permission to call the Cloud Billing
Budgets API. The SA must be bound directly on the **billing account** itself.

This was fixed by running:
```bash
gcloud billing accounts add-iam-policy-binding 01DA3A-863E5F-D24BB4 \
  --member="serviceAccount:terraform-org-admin@meelass-terraform-admin.iam.gserviceaccount.com" \
  --role="roles/billing.admin"
```

The distinction matters because billing accounts sit outside the normal
`organisation → folder → project` hierarchy — they are a parallel resource type
with their own IAM surface. Org-level billing roles control *linking* billing
accounts to projects; billing account-level roles control *managing* the billing
account itself (budgets, payments, reports).

---

## Related Documents

- `terraform/platform/folders/` — folder Terraform source
- `terraform/platform/org-policies/` — org policy Terraform source
- `terraform/platform/audit-logging/` — audit logging Terraform source
- `terraform/platform/billing-alerts/` — billing alerts Terraform source
- `docs/architecture/org-policies-reference.md` — full explanation of every policy
- `docs/decisions/ADR-004-folder-strategy.md` — why this folder structure
- `PROGRESS.md` — phase completion status and known gotchas
