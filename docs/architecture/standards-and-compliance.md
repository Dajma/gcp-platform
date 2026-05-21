# Standards & Compliance — Design Foundations

This document describes the industry standards, frameworks, and best practices applied to
this platform's design. Every architectural decision traces back to at least one of these.

---

## 1. Google Cloud Architecture Framework

Google's own opinionated framework for building reliable, secure, high-performing GCP environments.

**Applied patterns:**
- Hub-and-spoke Shared VPC topology — Google's recommended network pattern for multi-project environments
- Separate host and service projects for Shared VPC — network administration is isolated from workload administration
- Per-concern project isolation — blast radius containment over management convenience
- Private Google Access enabled on all subnets — workloads reach Google APIs without a public IP

---

## 2. CIS GCP Benchmark v2.0

The Center for Internet Security benchmark for GCP. The controls below are implemented or planned.

| CIS Control | Implementation | Phase |
|---|---|---|
| Audit logging for Admin Activity, Data Access, System Events | Org-level log sink to `logging-central` | Phase 1 |
| No primitive roles at project level or above | Org policy + IAM module enforces this | Phase 2 |
| OS Login enforced | Org policy: `compute.requireOsLogin` | Phase 1 |
| Shielded VMs enforced | Org policy: `compute.requireShieldedVm` | Phase 1 |
| Uniform bucket-level access on GCS | Applied to state bucket in bootstrap | Phase 0 |
| Public access prevention on GCS | Applied to state bucket in bootstrap | Phase 0 |
| Service account key creation restricted | Org policy: `iam.disableServiceAccountKeyCreation` | Phase 2 |
| Default service account auto-create disabled | Org policy: `iam.automaticIamGrantsForDefaultServiceAccounts` | Phase 2 |

Any deviation from CIS GCP Benchmark v2.0 will be documented here with a risk acceptance statement.

---

## 3. Google Cloud Security Foundations Blueprint

Google's enterprise reference architecture — the pattern used by Google's own largest customers.
This is the closest thing to "what Stripe/Shopify would run on GCP."

**Key elements adopted:**

| Blueprint element | Where implemented |
|---|---|
| Centralized logging project as dedicated security sink | `logging-central` project, Phase 4 |
| KMS in a project separate from the data it protects | `security-project` hosts KMS; app projects use CMEK | Phase 4 |
| Break-glass accounts with alert-on-use | IAM runbook + log-based metric alert | Phase 2 |
| Workload Identity everywhere — no exported SA keys | Enforced via org policy + module pattern | Phase 2 |
| Hierarchical firewall policies at org/folder level | Deny-by-default baseline in networking layer | Phase 3 |
| VPC Service Controls perimeter around prod | Prod perimeter in `security-project` | Phase 4 |
| Separate VPCs for prod and nonprod | `networking-host-prod` / `networking-host-nonprod` | Phase 3 |

---

## 4. SOC 2 Type II Alignment

Relevant trust service criteria addressed by this design.

| SOC 2 Criteria | Control | Implementation |
|---|---|---|
| CC6.1 — Logical access | Least-privilege IAM, group-based bindings, no shared accounts | Phase 2 |
| CC6.2 — Access provisioning | Group membership in Cloud Identity; quarterly review | Phase 2 |
| CC6.3 — Access removal | Group-based IAM — one removal revokes all project access | Phase 2 |
| CC7.2 — Monitoring | SCC, log-based metrics, drift detection, SLO burn rate alerts | Phase 4/8 |
| CC8.1 — Change management | Terraform PR approval gates; prod requires named approver | Phase 6 |
| CC9.2 — Vendor risk | All workloads private-by-default; VPC SC perimeter in prod | Phase 3/4 |
| A1.2 — Availability | SLOs defined before workloads deploy; PDBs on all critical services | Phase 8 |

---

## 5. ISO 27001 Alignment

| ISO 27001 Domain | Control | Implementation |
|---|---|---|
| A.8 — Asset management | Every resource labeled: `env`, `team`, `managed-by`, `cost-center` | All phases |
| A.9 — Access control | Least privilege, no shared accounts, break-glass documented | Phase 2 |
| A.10 — Cryptography | CMEK for all data stores, KMS key rotation policy, HSM-backed keys | Phase 4 |
| A.12 — Operations security | Drift detection, runbook per operation type, DR test cadence | Phase 10 |
| A.13 — Communications security | Private networking, TLS everywhere, no plaintext internal comms | Phase 3 |
| A.14 — Secure development | IaC security scanning (checkov/tfsec), Binary Authorization | Phase 6/7 |
| A.16 — Incident management | Break-glass procedure, SCC findings triage runbook, P1/P2/P3 severity | Phase 4/8 |
| A.17 — Business continuity | DR runbook, backup validation schedule, multi-zone GKE node pools | Phase 10 |

---

## 6. NIST SP 800-53 (implicit alignment)

Not explicitly targeted, but the design inherently satisfies several control families.

| NIST Control Family | Applied as |
|---|---|
| AC — Access Control | Least-privilege IAM, group-based bindings, WIF for CI/CD |
| AU — Audit and Accountability | Org-level audit log sinks, immutable log storage, log-based metric alerts |
| CM — Configuration Management | Terraform-managed state, drift detection, all changes via PR |
| IA — Identification & Authentication | Workload Identity, no static credentials, MFA on break-glass accounts |
| SC — System & Communications Protection | Defense-in-depth (7 layers), private networking, CMEK, VPC Service Controls |
| SI — System & Information Integrity | SCC continuous scanning, Binary Authorization, Shielded VMs |
| CP — Contingency Planning | DR runbooks, backup validation, multi-zone clusters |

---

## 7. Terraform Community Standards

| Standard | Source | Applied as |
|---|---|---|
| Standard Module Structure | HashiCorp documentation | Every module: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md` |
| `for_each` over `count` | HashiCorp best practices | All keyed resources use `for_each` — no positional indexing |
| Provider version pinning | Terraform community | `~>` constraints in every `versions.tf`; minimum TF version declared |
| Sensitive output marking | HashiCorp documentation | All secret/key outputs marked `sensitive = true` |
| Per-layer state isolation | Community / Google | One state file per logical layer — see ADR-001 |
| Module source pinning | HashiCorp documentation | Internal modules pinned via Git tags when promoted to shared use |

---

## Lab vs Production Deviations

Where the lab configuration intentionally diverges from the standard recommendation:

| Standard recommendation | Lab configuration | Reason | Risk |
|---|---|---|---|
| SCC Premium tier | Standard tier | ~$0.06/asset/month — too expensive for personal lab | Reduced threat detection coverage; acceptable in lab |
| Multi-region GCS state bucket | Single region (`us-central1`) | Cross-region replication cost | State loss if region fails; acceptable in lab |
| Cloud NAT logging enabled | Disabled | Per-GB egress logging cost | Reduced egress visibility; re-enable in prod |
| Separate state bucket per environment | Single bucket, separate prefixes | Lab simplification | Nonprod pipeline can read prod state prefixes; separate buckets in prod |
| Chronicle SIEM | Skipped | Very expensive ($) | No SIEM correlation in lab; documented prod design only |
| Cloud SQL HA (REGIONAL) | Single-zone (ZONAL) | ~$50/month saving | No automated failover in lab |
| Multi-zone GKE node pools | Single zone in lab | Cost | No zone-level redundancy in lab |

Every lab deviation is flagged inline with `# LAB:` / `# PROD:` comments in Terraform so
the gap between lab and production is always visible at the code level.

---

## Compliance Traceability

When a compliance audit requires evidence, the following artifacts map to controls:

| Evidence type | Location |
|---|---|
| Architecture decisions | `docs/decisions/ADR-*.md` |
| Network topology | `docs/diagrams/02-network-topology.md` |
| IAM model | `docs/diagrams/05-iam-model.md` |
| Security controls | `docs/diagrams/03-security-architecture.md` |
| Operational procedures | `docs/runbooks/*.md` |
| Change history | Git log — every change is a PR with plan output |
| Audit logs | `logging-central` project — BigQuery queryable |
| Threat model | `docs/threat-model/` |
