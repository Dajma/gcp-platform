# Org Policies Reference

All org policies enforced on the `meelass.com` organisation (`473689265669`).

Policies in the **"Set by Terraform"** group were applied in Phase 1 via
`terraform/platform/org-policies/`. Policies in the **"Google default"** group
were automatically applied by GCP when the organisation was created.

---

## Verify current state

```bash
# List all enforced policies
gcloud org-policies list --organization=473689265669 \
  --impersonate-service-account=terraform-org-admin@meelass-terraform-admin.iam.gserviceaccount.com

# Inspect a specific policy
gcloud org-policies describe compute.requireShieldedVm \
  --organization=473689265669 \
  --impersonate-service-account=terraform-org-admin@meelass-terraform-admin.iam.gserviceaccount.com
```

---

## IAM Policies

### `iam.disableServiceAccountKeyCreation` — Terraform

**What it does:** Blocks anyone from generating a downloadable JSON or P12 key
for any service account in the org.

**Threat mitigated:** Leaked static SA credentials. A downloaded key is a
long-lived credential with no expiry that gets committed to GitHub, pasted into
`.env` files, and distributed via Slack. Half of all major GCP breaches start
with a leaked SA key.

**Correct replacement:** Workload Identity Federation (WIF) for CI/CD pipelines;
SA impersonation (`gcloud auth application-default login --impersonate-service-account=...`)
for humans. Neither involves a downloadable credential file.

**What breaks if removed:** Nothing legitimate. Any workflow using
`gcloud iam service-accounts keys create` or the Console "Keys" tab should be
migrated to WIF.

---

### `iam.disableServiceAccountKeyUpload` — Terraform

**What it does:** Blocks uploading your own RSA public key to an existing
service account (the reverse direction of key creation).

**Threat mitigated:** Persistent backdoor creation. An attacker who already has
`iam.serviceAccountKeys.create` permission could upload their own key to an
existing SA, creating a backdoor that survives credential rotation and is
invisible to standard audits.

**What breaks if removed:** Nothing in normal operations. The only legitimate
use case is "bring your own key" (BYOK) SA authentication, which is obsolete
once WIF is in place.

---

### `iam.automaticIamGrantsForDefaultServiceAccounts` — Terraform

**What it does:** Stops GCP from automatically granting `roles/editor` to the
default Compute Engine and App Engine service accounts when a new project is
created.

**Threat mitigated:** Overprivileged default SAs. GCP historically created two
SAs automatically in every new project (Compute Engine default SA, App Engine
default SA) and granted both `roles/editor` — read/write access to almost every
GCP API. Any VM in that project would run as an SA with near-full project
permissions by default. This is one of the most dangerous GCP defaults ever
shipped.

**What breaks if removed:** Nothing you should rely on. If a VM needs to call
an API, it must have a dedicated SA with exactly the permissions it needs, not
a shared default with Editor.

---

### `iam.allowedPolicyMemberDomains` — Google default

**What it does:** Restricts who can be added to IAM bindings. Only identities
from approved domains (`meelass.com` and Google's own service account domains)
can be granted roles.

**Threat mitigated:** External or anonymous IAM grants. Without this, anyone
could bind `allUsers`, `allAuthenticatedUsers`, or an arbitrary Gmail to
`roles/editor` on a project — either by mistake or maliciously.

**Operational implication:** External contractors cannot be invited by personal
Gmail. They need a `@meelass.com` account or a temporary folder-level policy
exception with a defined expiry.

---

## Compute / VM Policies

### `compute.requireShieldedVm` — Terraform

**What it does:** Forces every new VM to have all three Shielded VM features
enabled: Secure Boot, vTPM (virtual Trusted Platform Module), and Integrity
Monitoring.

**Three distinct protections:**

| Feature | What it does |
|---|---|
| **Secure Boot** | VM only boots firmware and OS images that are cryptographically signed. Prevents bootkit/rootkit malware from loading before the OS starts. |
| **vTPM** | Stores cryptographic measurements of the boot sequence in a hardware-backed chip. If someone swaps the boot disk or tampers with the boot chain, the vTPM detects the change. |
| **Integrity Monitoring** | Baselines the boot sequence on first boot and alerts if it deviates on subsequent boots — for example, if a kernel module was injected. |

**Threat mitigated:** Boot-time attacks (bootkits, rootkits, firmware
implants), disk-swap attacks, kernel module injection.

**What breaks if removed:** VMs using custom images that predate Shielded VM
support (pre-2019 images). All modern OS images (Debian 12, Ubuntu 22.04, RHEL
9, Windows 2022) are Shielded-compatible.

---

### `compute.requireOsLogin` — Terraform

**What it does:** Enforces that SSH access to VMs goes through OS Login
(IAM-based SSH) rather than static SSH keys stored in instance metadata or
project metadata.

**Old model vs. new model:**

| | Old model (blocked) | New model (OS Login) |
|---|---|---|
| Key management | Upload public key to metadata | Grant `roles/compute.osLogin` to a user or group |
| Revocation | Manually delete key from metadata | Remove IAM binding — revoked in seconds |
| Audit trail | Nothing — no log of who connected | Cloud Audit Logs record every SSH grant |
| Off-boarding | Easy to forget to remove keys | Removing the user from the IAM group revokes all access |

**Threat mitigated:** Persistent SSH access via forgotten static keys;
unaudited SSH sessions; orphaned access after team member departure.

**What breaks if removed:** Any automation that uses `--metadata=ssh-keys=...`
or the Console's "Add SSH key" feature. Replace with `gcloud compute ssh`
(which uses OS Login automatically) or IAP Tunnel SSH.

---

### `compute.skipDefaultNetworkCreation` — Terraform

**What it does:** Suppresses the auto-creation of the default VPC when a new
project is created.

**What GCP would do without this policy:** Every new project gets a
`default` VPC with subnets pre-created in every region and three default
firewall rules: allow SSH (TCP/22) from `0.0.0.0/0`, allow RDP (TCP/3389) from
`0.0.0.0/0`, and allow ICMP from `0.0.0.0/0`. SSH and RDP open to the entire
internet is the default, not the exception.

**Threat mitigated:** Internet-exposed SSH/RDP by default; VMs being accessible
before teams have a chance to harden them.

**Operational implication:** New projects start with zero network resources.
Workload projects must explicitly attach to the Shared VPC (Phase 3). This is
the correct behaviour — intentional network design, not accidental topology.

---

### `compute.vmExternalIpAccess` — Terraform

**What it does:** Denies assignment of external (public) IP addresses to any
VM across the entire org.

**Threat mitigated:** VMs directly reachable from the internet. A VM with an
external IP bypasses all the cloud-native perimeter controls (load balancer,
Cloud Armor, IAP). Any port open on that VM is directly scannable from anywhere
in the world.

**Correct architecture:**
- **Outbound internet access:** Cloud NAT (in the hub VPC, Phase 3)
- **Inbound HTTP/HTTPS:** Cloud Load Balancer → Cloud Armor → private backend
- **Inbound SSH/admin:** IAP Tunnel — no public IP required, all access goes
  through Google's infrastructure and is logged in Cloud Audit Logs

**What breaks if removed:** Developer habit of SSHing directly to a VM by IP.
Use `gcloud compute ssh` via IAP instead.
**Sandbox exception:** The `sandbox/` folder has this policy overridden to allow
external IPs for developer experimentation.

---

### `compute.restrictProtocolForwardingCreationForTypes` — Google default

**What it does:** Restricts which types of protocol forwarding rules can be
created — specifically blocks forwarding rules that target external IP addresses.

**Threat mitigated:** Protocol forwarding bypass. Protocol forwarding rules
(used by internal load balancers and network appliances) can route traffic to
external IPs. Without this policy, the `vmExternalIpAccess` deny can be
side-stepped by creating a forwarding rule that points to an externally-routable
address. This closes that door.

**What breaks if removed:** Advanced networking scenarios that require external
protocol forwarding. Rarely needed.

---

### `compute.setNewProjectDefaultToZonalDNSOnly` — Google default

**What it does:** Sets newly created projects to use zonal DNS for internal VM
name resolution, instead of the legacy global DNS scheme.

**Legacy vs. zonal:**

| | Legacy global DNS | Zonal DNS |
|---|---|---|
| VM hostname format | `vm-name.c.project-id.internal` | `vm-name.zone.c.project-id.internal` |
| Scope | Global across all zones | Scoped to the specific zone |
| Collision risk | Two VMs with the same name in different zones collide | No collision possible |

**Threat mitigated:** Internal DNS hijacking via name collision — an attacker in
one zone creating a VM with the same name as a trusted VM in another zone,
causing DNS to resolve to the wrong host.

**What breaks if removed:** Nothing for new workloads. This org has no legacy
DNS workloads to protect.

---

## Storage Policies

### `storage.uniformBucketLevelAccess` — Terraform

**What it does:** Disables per-object ACLs (Access Control Lists) on all GCS
buckets. All access control must go through IAM only.

**Two permission systems GCS originally had:**

| | IAM | ACLs (legacy) |
|---|---|---|
| Scope | Bucket or project | Per-object (individual file) |
| Visibility | `gcloud iam` / audit logs | Hidden from standard IAM audits |
| Granularity | Coarse (bucket-level) | Very fine (single object) |
| Danger | Requires explicit grant | Easy to accidentally make one file public |

Without this policy, a developer could `gsutil acl set public-read gs://bucket/sensitive-file.csv`
and that file would be publicly accessible with no trace in IAM audit logs.

**Threat mitigated:** Silent per-object data exposure; audit gaps in access reviews.

**What breaks if removed:** Any code using `gsutil acl set` or the older ACL
API. All access should use `roles/storage.objectViewer` and similar IAM roles.

---

### `storage.publicAccessPrevention` — Terraform

**What it does:** Makes it physically impossible to grant `allUsers` or
`allAuthenticatedUsers` access to a GCS bucket, even if an IAM binding is
explicitly created.

**Threat mitigated:** The classic "public S3/GCS bucket" data breach — the most
common cloud security incident type. This policy is a hard guardrail: even if a
developer deliberately runs `gcloud storage buckets add-iam-policy-binding ... --member=allUsers`,
the API will reject it.

**Relationship to `uniformBucketLevelAccess`:** Complementary, not redundant.
`uniformBucketLevelAccess` removes ACLs. `publicAccessPrevention` blocks public
IAM grants. You need both.

**What breaks if removed:** Any use case requiring public GCS hosting (static
website, public artifact downloads). The correct architecture is a load balancer
with a CDN in front of a private bucket — not a raw public bucket.

---

## Geography Policy

### `gcp.resourceLocations` — Terraform

**What it does:** Restricts where GCP resources can be physically created.
Only `us-central1` (Iowa, USA) and `global` (for truly global resources) are
permitted. Attempting to create a Cloud SQL instance in `europe-west1` or a GKE
cluster in `asia-east1` will be rejected at the API level.

**`global` scope covers:**
- Cloud Armor policies (no region)
- Global Cloud DNS zones
- GCS multi-region buckets (`US`, `EU`, `ASIA` locations are blocked — single region `us-central1` only)
- IAM policies (always global)

**Three reasons this matters:**

1. **Data residency:** Customer data cannot accidentally leave North America.
   Regulatory requirements (PIPEDA for Canadian customers, state privacy laws)
   may mandate this.

2. **Cost:** Cross-region traffic is billed per-GB. All resources in one region
   means zero cross-region egress within the platform.

3. **Operational simplicity:** One region = one monitoring plane, one quota set,
   one set of runbooks. Multi-region adds complexity that a lab environment
   doesn't need yet.

**Adding a second region (future):** Edit `allowed_locations` in
`terraform/platform/org-policies/terraform.tfvars`, add `"in:us-east1-locations"`,
and run `terraform apply` from `terraform/platform/org-policies/`. The change
propagates to all folders and projects in under 10 minutes.

**What breaks if removed:** Nothing — it expands what's allowed, not what's
forbidden.

---

## Essential Contacts Policy

### `essentialcontacts.allowedContactDomains` — Google default

**What it does:** Restricts which email domains can be registered as Essential
Contacts — the addresses GCP uses to send security vulnerability disclosures,
service disruption notices, billing threshold alerts, and legal/compliance
notifications.

**Threat mitigated:** Security notifications going to external or uncontrolled
parties. If a contractor's Gmail is registered as the security contact and GCP
discovers a critical vulnerability in your environment, the disclosure goes to
that Gmail instead of your security team. This policy locks contacts to
`@meelass.com` addresses only.

**What breaks if removed:** Nothing actively. You simply cannot register an
external email as an Essential Contact — which is the correct behaviour.

---

## Policy Reference Summary

| Policy | Source | Type | Threat mitigated |
|---|---|---|---|
| `iam.disableServiceAccountKeyCreation` | Terraform | Boolean | Leaked static SA credentials |
| `iam.disableServiceAccountKeyUpload` | Terraform | Boolean | Backdoor SA key injection |
| `iam.automaticIamGrantsForDefaultServiceAccounts` | Terraform | Boolean | Default SAs with Editor role |
| `iam.allowedPolicyMemberDomains` | Google default | List | External/anonymous IAM grants |
| `compute.requireShieldedVm` | Terraform | Boolean | Boot-time malware, disk-swap attacks |
| `compute.requireOsLogin` | Terraform | Boolean | Persistent static SSH keys |
| `compute.skipDefaultNetworkCreation` | Terraform | Boolean | Default VPC with open SSH/RDP |
| `compute.vmExternalIpAccess` | Terraform | List (deny all) | VMs directly exposed to internet |
| `compute.restrictProtocolForwardingCreationForTypes` | Google default | List | Protocol forwarding bypass |
| `compute.setNewProjectDefaultToZonalDNSOnly` | Google default | Boolean | Internal DNS name collision |
| `storage.uniformBucketLevelAccess` | Terraform | Boolean | Silent per-object ACL grants |
| `storage.publicAccessPrevention` | Terraform | Boolean | Public bucket data exposure |
| `gcp.resourceLocations` | Terraform | List (allow) | Data residency violations, region sprawl |
| `essentialcontacts.allowedContactDomains` | Google default | List | Security notices reaching wrong party |

---

## Related documents

- `terraform/platform/org-policies/` — Terraform source for the 10 managed policies
- [ADR-004](../decisions/ADR-004-folder-strategy.md) — Folder hierarchy (policies inherit down the folder tree)
- `docs/architecture/standards-and-compliance.md` — CIS GCP Benchmark mapping
