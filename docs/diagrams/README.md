# Platform Diagrams

All diagrams use [Mermaid](https://mermaid.js.org/) and render natively in GitHub, GitLab,
and VS Code (with the Mermaid Preview extension).

| Diagram | What it covers |
|---|---|
| [01 — Org Hierarchy](01-org-hierarchy.md) | GCP resource hierarchy: org → folders → projects, org-level controls |
| [02 — Network Topology](02-network-topology.md) | Hub-and-spoke VPC, subnets, firewall rules, egress path |
| [03 — Security Architecture](03-security-architecture.md) | Defense-in-depth layers, IAM model, key/secret management, threat model |
| [04 — CI/CD Pipeline](04-cicd-pipeline.md) | GitHub Actions flow, WIF credential exchange, environment separation |
| [05 — IAM Model](05-iam-model.md) | Identity hierarchy, SA strategy, group-based IAM, break-glass procedure |
| [06 — GKE Architecture](06-gke-architecture.md) | Cluster topology, Workload Identity, GitOps/ArgoCD, Binary Authorization |
| [07 — Observability Stack](07-observability-stack.md) | Log sinks, metrics, SLO framework, alerting pipeline |

## Keeping Diagrams Current

Update the relevant diagram at the end of each phase. The diagrams are the canonical
visual reference for the platform — they should match deployed state at all times.

| Phase | Diagrams to update |
|---|---|
| 1 — Org & Folders | 01-org-hierarchy |
| 2 — IAM | 05-iam-model |
| 3 — Networking | 02-network-topology |
| 4 — Security | 03-security-architecture |
| 5 — Project Factory | 01-org-hierarchy |
| 6 — CI/CD | 04-cicd-pipeline |
| 7 — GKE | 06-gke-architecture |
| 8 — Observability | 07-observability-stack |
