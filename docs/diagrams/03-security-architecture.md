# Diagram: Security Architecture

## Defense-in-Depth Layers

```mermaid
graph TD
    subgraph LAYER0["Layer 0 — Perimeter"]
        CA["Cloud Armor<br/>WAF · DDoS protection<br/>IP allowlist/denylist"]
        VPC_SC["VPC Service Controls<br/>API-level perimeter<br/>(prod only, Phase 4)"]
    end

    subgraph LAYER1["Layer 1 — Identity & Access"]
        WIF["Workload Identity Federation<br/>Zero static credentials<br/>CI/CD + app workloads"]
        IAM["IAM — Least Privilege<br/>No primitive roles<br/>Group-based bindings only"]
        BG["Break-Glass Accounts<br/>2 accounts, separate MFA<br/>Alert on any use"]
        OSLOGIN["OS Login<br/>Enforced via org policy<br/>No SSH keys on VMs"]
    end

    subgraph LAYER2["Layer 2 — Network"]
        PRIV["Private-by-Default<br/>No public IPs on workloads<br/>Cloud NAT for egress"]
        HFW["Hierarchical Firewall<br/>Deny-by-default baseline"]
        PSA["Private Service Access<br/>Cloud SQL, Memorystore<br/>never exposed to internet"]
    end

    subgraph LAYER3["Layer 3 — Compute"]
        SHIELDED["Shielded VMs<br/>Secure Boot · vTPM<br/>Integrity Monitoring"]
        BINAUTH["Binary Authorization<br/>All container images attested<br/>No unverified images in prod"]
        PSP["Pod Security Standards<br/>restricted profile<br/>No privileged containers"]
    end

    subgraph LAYER4["Layer 4 — Data"]
        CMEK["CMEK<br/>Customer-managed keys<br/>All data stores in prod"]
        KMS["Cloud KMS<br/>Keys in dedicated project<br/>Separated from data"]
        SM["Secret Manager<br/>All secrets centralised<br/>Version + audit every access"]
    end

    subgraph LAYER5["Layer 5 — Detection & Response"]
        SCC["Security Command Center<br/>Misconfig detection<br/>Threat detection"]
        AUDIT["Cloud Audit Logs<br/>Admin Activity<br/>Data Access<br/>System Events"]
        LOGMET["Log-Based Metrics<br/>Failed auth alerts<br/>Privilege escalation<br/>Config changes"]
    end

    LAYER0 --> LAYER1
    LAYER1 --> LAYER2
    LAYER2 --> LAYER3
    LAYER3 --> LAYER4
    LAYER4 --> LAYER5

    style LAYER0 fill:#FFCDD2,stroke:#C62828
    style LAYER1 fill:#FFE0B2,stroke:#E65100
    style LAYER2 fill:#FFF9C4,stroke:#F9A825
    style LAYER3 fill:#DCEDC8,stroke:#558B2F
    style LAYER4 fill:#B2EBF2,stroke:#00838F
    style LAYER5 fill:#E1BEE7,stroke:#6A1B9A
```

## IAM Model

```mermaid
graph LR
    subgraph HUMANS["Human Access"]
        ADMIN_GRP["group: platform-admins@<br/>roles/resourcemanager.folderAdmin<br/>roles/iam.securityAdmin"]
        DEV_GRP["group: developers@<br/>roles/viewer (nonprod only)<br/>roles/logging.viewer"]
        SECOPS_GRP["group: secops@<br/>roles/securitycenter.admin<br/>roles/logging.admin"]
        BG_ACCT["break-glass-1@<br/>break-glass-2@<br/>roles/owner (org level)<br/>Alert on every use"]
    end

    subgraph CICD["CI/CD Identity"]
        GH_OIDC["GitHub OIDC Token<br/>(ephemeral, per-job)"]
        WIF_POOL["WIF Identity Pool<br/>per environment<br/>not shared prod/nonprod"]
        TF_SA["terraform-apply-sa@<br/>roles/specific per layer<br/>Impersonation only"]

        GH_OIDC -->|"exchanges via WIF"| WIF_POOL
        WIF_POOL -->|"impersonates"| TF_SA
    end

    subgraph WORKLOADS["Workload Identity (GKE)"]
        KSA["Kubernetes ServiceAccount<br/>per workload"]
        GSA["GCP ServiceAccount<br/>per workload<br/>minimum permissions"]
        WI_BINDING["Workload Identity Binding<br/>KSA → GSA<br/>no key export"]

        KSA -->|"annotated with"| WI_BINDING
        WI_BINDING -->|"projects to"| GSA
    end

    style HUMANS fill:#E3F2FD,stroke:#1565C0
    style CICD fill:#E8F5E9,stroke:#2E7D32
    style WORKLOADS fill:#FFF3E0,stroke:#E65100
```

## Secret & Key Management Flow

```mermaid
flowchart LR
    DEV["Developer<br/>(local)"]
    CI["CI Pipeline<br/>(GitHub Actions)"]
    APP["Application<br/>(GKE Pod)"]

    subgraph MGMT["secret-project / KMS"]
        SM["Secret Manager<br/>versioned secrets<br/>IAM-controlled access<br/>audit every read"]
        KMS["Cloud KMS<br/>CMEK keys<br/>per-environment keyrings<br/>annual rotation"]
    end

    subgraph DATA["Data Stores (prod)"]
        SQL["Cloud SQL<br/>CMEK encrypted"]
        GCS_DATA["Cloud Storage<br/>CMEK encrypted"]
        BQ["BigQuery<br/>CMEK encrypted"]
    end

    DEV -->|"impersonate SA<br/>gcloud secrets access"| SM
    CI -->|"WIF token → SA<br/>Secret Manager API"| SM
    APP -->|"Workload Identity<br/>Secret Manager API"| SM

    SM -->|"returns plaintext<br/>over TLS in-memory"| APP
    KMS -->|"wraps data encryption keys"| SQL
    KMS --> GCS_DATA
    KMS --> BQ

    style MGMT fill:#E1BEE7,stroke:#6A1B9A
    style DATA fill:#B2EBF2,stroke:#00838F
```

## Threat Model Summary

| Threat | Likelihood | Impact | Control |
|---|---|---|---|
| Stolen CI credentials | Medium | Critical | WIF eliminates static credentials |
| Rogue insider | Low | Critical | Org policies + IAM least-privilege + audit logs |
| Supply chain (container image) | Medium | High | Binary Authorization + Artifact Registry only |
| Data exfiltration via API | Medium | High | VPC Service Controls (prod perimeter) |
| Misconfigured public resource | High | High | Org policy: deny public access (GCS, SQL) |
| Log tampering | Low | High | Logs routed to immutable sinks immediately |
| KMS key compromise | Very Low | Critical | Keys in isolated project, HSM-backed, rotation |
| Privilege escalation via SA | Low | High | No key exports, impersonation requires IAM binding |
| DDoS / web attack | Medium | Medium | Cloud Armor in front of all external LBs |
