# System Context — GCP Platform Architecture

## Platform Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  GCP Organization  (org_id: TBD)                                                │
│  Domain: TBD                                                                    │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  Folder: infrastructure/                                                 │   │
│  │  ┌─────────────────────────┐  ┌─────────────────────────┐               │   │
│  │  │  networking-host-prod   │  │  networking-host-nonprod│               │   │
│  │  │  Shared VPC (prod)      │  │  Shared VPC (nonprod)   │               │   │
│  │  │  Cloud NAT              │  │  Cloud NAT              │               │   │
│  │  │  Cloud DNS              │  │  Cloud DNS              │               │   │
│  │  │  Hierarchical FW        │  │  Hierarchical FW        │               │   │
│  │  └─────────────────────────┘  └─────────────────────────┘               │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  Folder: security/                                                       │   │
│  │  ┌─────────────────────────┐  ┌─────────────────────────┐               │   │
│  │  │  logging-central        │  │  security-project       │               │   │
│  │  │  Log sinks (all projs)  │  │  KMS keyrings           │               │   │
│  │  │  BigQuery (analytics)   │  │  Secret Manager         │               │   │
│  │  │  GCS (cold archive)     │  │  SCC configuration      │               │   │
│  │  │  Log-based metrics      │  │  Binary Auth policy     │               │   │
│  │  └─────────────────────────┘  └─────────────────────────┘               │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  Folder: shared-services/                                                │   │
│  │  ┌─────────────────────────┐  ┌─────────────────────────┐               │   │
│  │  │  cicd-platform          │  │  shared-services        │               │   │
│  │  │  Artifact Registry      │  │  Internal DNS           │               │   │
│  │  │  GitHub WIF provider    │  │  Shared tooling APIs    │               │   │
│  │  │  Cloud Build (optional) │  └─────────────────────────┘               │   │
│  │  └─────────────────────────┘                                            │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌───────────────────────────┐  ┌───────────────────────────┐                  │
│  │  Folder: prod/            │  │  Folder: nonprod/         │                  │
│  │  ┌─────────────────────┐  │  │  ┌─────────────────────┐  │                  │
│  │  │  gke-prod           │  │  │  │  gke-nonprod        │  │                  │
│  │  │  Private GKE        │  │  │  │  Private GKE        │  │                  │
│  │  │  Workload Identity  │  │  │  │  Workload Identity  │  │                  │
│  │  │  Binary Auth ON     │  │  │  │  Binary Auth ON     │  │                  │
│  │  │  Attached to prod   │  │  │  │  Attached to nonprod│  │                  │
│  │  │  Shared VPC         │  │  │  │  Shared VPC         │  │                  │
│  │  └─────────────────────┘  │  │  └─────────────────────┘  │                  │
│  │  ┌─────────────────────┐  │  │  ┌─────────────────────┐  │                  │
│  │  │  app-{name}-prod    │  │  │  │  app-{name}-nonprod │  │                  │
│  │  │  (per application)  │  │  │  │  (per application)  │  │                  │
│  │  └─────────────────────┘  │  │  └─────────────────────┘  │                  │
│  └───────────────────────────┘  └───────────────────────────┘                  │
│                                                                                 │
│  ┌──────────────────┐                                                           │
│  │  Folder: sandbox/│                                                           │
│  │  sandbox project │  (auto-cleanup, unrestricted experimentation)             │
│  └──────────────────┘                                                           │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  Org-level controls (no folder — applies everywhere)                     │   │
│  │  • Audit logging: Admin Activity + Data Access + System Events           │   │
│  │  • Org policies: restrictive baseline (Phase 1)                          │   │
│  │  • Hierarchical firewall: deny-by-default baseline                       │   │
│  │  • SCC: Standard tier minimum                                            │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Networking — Hub-and-Spoke

```
Internet
    │
    ▼
Cloud Armor (Cloud LB + WAF)
    │
    ▼
┌───────────────────────────────────────────────────────┐
│  networking-host-prod (Shared VPC Host)                │
│                                                        │
│  VPC: prod-vpc  (10.0.0.0/8)                          │
│  ┌────────────────┐  ┌────────────────┐               │
│  │ subnet-gke-prod│  │ subnet-sql-prod│               │
│  │ us-central1    │  │ us-central1    │               │
│  │ 10.0.0.0/20    │  │ 10.0.16.0/24  │               │
│  │ + Pod range    │  │ Private SA     │               │
│  │ 10.1.0.0/16    │  └────────────────┘               │
│  │ + Svc range    │                                    │
│  │ 10.2.0.0/20    │                                    │
│  └────────────────┘                                    │
│                                                        │
│  Cloud NAT → Internet (all egress routed here)        │
│  Cloud DNS → Private zone: internal.example.com       │
│  Cloud VPN / Interconnect → On-prem (future)          │
│                                                        │
│  Service Projects attached (via xpnAdmin):            │
│  ├── gke-prod         (uses subnet-gke-prod)          │
│  └── app-{name}-prod  (uses appropriate subnet)       │
└───────────────────────────────────────────────────────┘

[Identical hub for nonprod: networking-host-nonprod, 10.64.0.0/8]
```

---

## Security Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Threat Surface → Control                               │
│                                                         │
│  External attacker → Cloud Armor + Private networking   │
│  Stolen credential → WIF + short-lived tokens           │
│  Rogue insider → Org policies + IAM least-privilege     │
│  Data exfil → VPC Service Controls (prod perimeter)     │
│  Supply chain → Binary Authorization + Artifact Reg     │
│  Audit evasion → Centralized immutable log sinks        │
│  Key compromise → CMEK + KMS in separate project        │
│  Config drift → Terraform + nightly drift detection     │
└─────────────────────────────────────────────────────────┘
```

---

## CI/CD Flow

```
Developer pushes code
        │
        ▼
GitHub PR opened
        │
        ├── validate job (fmt, validate, tflint)
        ├── security-scan job (checkov, tfsec, OPA)
        └── plan job (terraform plan → PR comment)
                │
                ▼ (merge to main)
        apply-nonprod job (auto, WIF → SA impersonation)
                │
                ▼ (manual approval gate)
        apply-prod job (requires GitHub environment approval)
                │
        nightly: drift-detect job (state vs real infra)
                │
        nightly: docs-gen job (terraform-docs auto-PR)
```

---

## Phase Build Order

```
Phase 0: Bootstrap (manual)
    │
    ▼
Phase 1: Org + Folder Hierarchy + Org Policies + Audit Logging
    │
    ▼
Phase 2: IAM Foundation (groups, break-glass, SA strategy)
    │
    ▼
Phase 3: Networking (VPCs, Shared VPC, NAT, DNS, FW)
    │
    ▼
Phase 4: Security (KMS, Secret Manager, SCC, log sinks)
    │
    ▼
Phase 5: Project Factory (gcp-project module, workload projects)
    │
    ▼
Phase 6: CI/CD (GitHub Actions, WIF, Artifact Registry)
    │
    ▼
Phase 7: GKE (private clusters, WI, Binary Auth, GitOps)
    │
    ▼
Phase 8: Observability (dashboards, SLOs, alerting as code)
    │
    ▼
Phase 9: Data & Storage (Cloud SQL, GCS lifecycle, CMEK)
    │
    ▼
Phase 10: Day-2 (runbooks, PRR, DR test, IAM review)
```

---

*Last updated: Phase 0 — 2026-05-20*
*Next update: Phase 1 completion*
