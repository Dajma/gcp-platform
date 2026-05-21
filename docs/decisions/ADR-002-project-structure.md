# ADR-002: Multi-Project Topology

**Status:** Accepted
**Date:** 2026-05-20
**Phase:** 0

## Context

GCP's resource hierarchy allows flexible project organization. The choice of how many
projects to use and how to structure them has long-term consequences for security,
cost visibility, blast radius, and operational complexity.

Common approaches in the industry range from "one project per org" (bad) to
"one project per microservice per environment" (impractical at small scale).

We are targeting a pattern used by companies running 10–100+ internal teams on GCP.

## Decision

Use a **dedicated-project-per-concern** topology with the following core projects:

| Project | Purpose | Folder |
|---|---|---|
| `{prefix}-networking-host-prod` | Shared VPC host, prod | infrastructure/ |
| `{prefix}-networking-host-nonprod` | Shared VPC host, nonprod | infrastructure/ |
| `{prefix}-logging-central` | Centralized log sinks, BigQuery, GCS archive | security/ |
| `{prefix}-security` | SCC, KMS, Secret Manager, IAM tooling | security/ |
| `{prefix}-cicd-platform` | GitHub Actions WIF, Artifact Registry | shared-services/ |
| `{prefix}-shared-services` | Cloud DNS, shared internal tooling | shared-services/ |
| `{prefix}-gke-prod` | GKE cluster, prod workloads | prod/ |
| `{prefix}-gke-nonprod` | GKE cluster, dev/staging workloads | nonprod/ |
| `{prefix}-terraform-admin` | Terraform SA, state bucket | (top-level, manual) |
| `{prefix}-sandbox` | Free-form experimentation | sandbox/ |

Application workloads get `{prefix}-app-{name}-prod` and `{prefix}-app-{name}-nonprod`
as they are introduced.

## Rationale

**Why separate networking-host projects:**
- Shared VPC _requires_ a host project; the network lives in the host, workloads in service projects
- Separating prod and nonprod host projects enforces the trust boundary at the VPC level —
  a compromised nonprod SA cannot touch prod networking

**Why a separate logging-central project:**
- Log sinks aggregate from all other projects → this project has broad read access to logs
- Isolating it limits the blast radius of a logging system compromise
- BigQuery and GCS for log storage should not compete with workload resource quotas
- SOC 2 / ISO 27001 commonly require that security logs be stored in a separate, restricted account

**Why a separate security project:**
- KMS keys should not be in the same project as the data they protect — if the project is
  deleted, you lose access to encrypted data
- SCC and policy tooling is a high-privilege surface; isolating it limits lateral movement risk

**Why separate CI/CD and shared-services projects:**
- CI/CD pipelines need elevated permissions (project creation, artifact publishing) —
  blast radius isolation prevents a pipeline compromise from touching unrelated workloads
- Artifact Registry in CI/CD project means image provenance is controlled by the platform team,
  not individual app teams

## Tradeoffs

- More projects = more management overhead (API enablement, billing linkage, IAM bindings)
- Mitigated in Phase 5 by the `gcp-project` Terraform module (project factory)
- Cross-project networking requires Shared VPC attachment setup (slightly more complex than single-project)
- Mitigated by the vpc-shared module in Phase 3

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| **Single project** | No blast radius isolation; VPC Service Controls require project boundaries; billing not separable by function; a single compromised SA can affect everything |
| **Two projects (prod/nonprod)** | Better than one, but security/networking/logging share blast radius with workloads; cannot implement VPC Service Controls perimeters effectively |
| **One project per microservice** | Impractical at this stage; network and IAM complexity explodes; quota management nightmare; fine for very large orgs with dedicated platform teams per service |
| **GCP Workload Identity pools for isolation** | WIF pools provide identity isolation but not resource blast radius isolation; you still need project separation for VPC Service Controls and quota management |

## Consequences

- All Terraform must be aware of project boundaries when creating cross-project resources
- The project factory module (Phase 5) must be built before application projects are created
- Shared VPC attachments must be explicit — no implicit cross-project network access
- Billing exports (Phase 8) can be segmented by project to show per-concern costs
- VPC Service Controls perimeters (Phase 4) align naturally with this project structure
