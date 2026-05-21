# Diagram: GCP Organization Hierarchy

> Renders in GitHub, GitLab, and VS Code with the Mermaid extension.

## Resource Hierarchy

```mermaid
graph TD
    ORG["🏢 GCP Organization<br/>(org_domain)"]

    ORG --> INFRA["📁 infrastructure/"]
    ORG --> SEC["📁 security/"]
    ORG --> SS["📁 shared-services/"]
    ORG --> PROD["📁 prod/"]
    ORG --> NONPROD["📁 nonprod/"]
    ORG --> SANDBOX["📁 sandbox/"]

    INFRA --> NET_PROD["📦 networking-host-prod<br/>Shared VPC host<br/>Cloud NAT · Cloud DNS"]
    INFRA --> NET_NONPROD["📦 networking-host-nonprod<br/>Shared VPC host<br/>Cloud NAT · Cloud DNS"]

    SEC --> LOG["📦 logging-central<br/>Log sinks (all projects)<br/>BigQuery · GCS archive"]
    SEC --> SECPROJ["📦 security-project<br/>KMS · Secret Manager<br/>SCC · Binary Auth policy"]

    SS --> CICD["📦 cicd-platform<br/>Artifact Registry<br/>GitHub WIF provider"]
    SS --> SHARED["📦 shared-services<br/>Cloud DNS (private)<br/>Shared internal APIs"]

    PROD --> GKE_PROD["📦 gke-prod<br/>Private GKE cluster<br/>Workload Identity<br/>Binary Auth ON"]
    PROD --> APP_PROD["📦 app-{name}-prod<br/>(per application)<br/>Attached to prod VPC"]

    NONPROD --> GKE_NONPROD["📦 gke-nonprod<br/>Private GKE cluster<br/>Workload Identity"]
    NONPROD --> APP_NONPROD["📦 app-{name}-nonprod<br/>(per application)<br/>Attached to nonprod VPC"]

    SANDBOX --> SBX["📦 sandbox<br/>Free-form experiments<br/>Auto-cleanup policy"]

    style ORG fill:#4285F4,color:#fff,stroke:#2956a3
    style INFRA fill:#EA4335,color:#fff,stroke:#b31412
    style SEC fill:#EA4335,color:#fff,stroke:#b31412
    style SS fill:#FBBC04,color:#000,stroke:#c69500
    style PROD fill:#34A853,color:#fff,stroke:#1e7e34
    style NONPROD fill:#34A853,color:#fff,stroke:#1e7e34
    style SANDBOX fill:#9AA0A6,color:#fff,stroke:#6b7075
```

## Folder Purpose Summary

| Folder | Trust Level | Network | Contains |
|---|---|---|---|
| `infrastructure/` | High | Hub VPCs | Shared VPC host projects only |
| `security/` | High | Attached to prod VPC | Logging, KMS, SCC, Secret Manager |
| `shared-services/` | Medium-High | Attached to nonprod VPC | CI/CD, Artifact Registry, DNS |
| `prod/` | High | Attached to prod VPC | All production workloads |
| `nonprod/` | Medium | Attached to nonprod VPC | Dev, staging workloads |
| `sandbox/` | Low | Standalone (no Shared VPC) | Unrestricted experiments |

## Org-Level Controls (apply to all folders)

```mermaid
graph LR
    ORG_POLICY["Org Policies<br/>(Phase 1)"]
    AUDIT["Audit Logging<br/>Admin Activity<br/>Data Access<br/>System Events"]
    SCC["Security Command Center<br/>Standard tier"]
    BILLING["Billing Alerts<br/>$10 / $25 / $50 / $100"]
    HFW["Hierarchical Firewall<br/>Deny-by-default baseline"]

    ORG_POLICY --> |"restricts all projects"| SCOPE["All Projects<br/>in all folders"]
    AUDIT --> |"sinks to"| SCOPE
    SCC --> |"scans"| SCOPE
    HFW --> |"applies to"| SCOPE

    style SCOPE fill:#E8F5E9,stroke:#34A853
```
