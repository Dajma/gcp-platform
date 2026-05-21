# Diagram: Security Architecture

## Defense-in-Depth Layers

```mermaid
graph TD
    subgraph LAYER0["Layer 0 — Perimeter"]
        CA["Cloud Armor\nWAF · DDoS protection\nIP allowlist/denylist"]
        VPC_SC["VPC Service Controls\nAPI-level perimeter\n(prod only, Phase 4)"]
    end

    subgraph LAYER1["Layer 1 — Identity & Access"]
        WIF["Workload Identity Federation\nZero static credentials\nCI/CD + app workloads"]
        IAM["IAM — Least Privilege\nNo primitive roles\nGroup-based bindings only"]
        BG["Break-Glass Accounts\n2 accounts, separate MFA\nAlert on any use"]
        OSLOGIN["OS Login\nEnforced via org policy\nNo SSH keys on VMs"]
    end

    subgraph LAYER2["Layer 2 — Network"]
        PRIV["Private-by-Default\nNo public IPs on workloads\nCloud NAT for egress"]
        HFW["Hierarchical Firewall\nDeny-by-default baseline"]
        PSA["Private Service Access\nCloud SQL, Memorystore\nnever exposed to internet"]
    end

    subgraph LAYER3["Layer 3 — Compute"]
        SHIELDED["Shielded VMs\nSecure Boot · vTPM\nIntegrity Monitoring"]
        BINAUTH["Binary Authorization\nAll container images attested\nNo unverified images in prod"]
        PSP["Pod Security Standards\nrestricted profile\nNo privileged containers"]
    end

    subgraph LAYER4["Layer 4 — Data"]
        CMEK["CMEK\nCustomer-managed keys\nAll data stores in prod"]
        KMS["Cloud KMS\nKeys in dedicated project\nSeparated from data"]
        SM["Secret Manager\nAll secrets centralised\nVersion + audit every access"]
    end

    subgraph LAYER5["Layer 5 — Detection & Response"]
        SCC["Security Command Center\nMisconfig detection\nThreat detection"]
        AUDIT["Cloud Audit Logs\nAdmin Activity\nData Access\nSystem Events"]
        LOGMET["Log-Based Metrics\nFailed auth alerts\nPrivilege escalation\nConfig changes"]
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
        ADMIN_GRP["group: platform-admins@\nroles/resourcemanager.folderAdmin\nroles/iam.securityAdmin"]
        DEV_GRP["group: developers@\nroles/viewer (nonprod only)\nroles/logging.viewer"]
        SECOPS_GRP["group: secops@\nroles/securitycenter.admin\nroles/logging.admin"]
        BG_ACCT["break-glass-1@\nbreak-glass-2@\nroles/owner (org level)\nAlert on every use"]
    end

    subgraph CICD["CI/CD Identity"]
        GH_OIDC["GitHub OIDC Token\n(ephemeral, per-job)"]
        WIF_POOL["WIF Identity Pool\nper environment\nnot shared prod/nonprod"]
        TF_SA["terraform-apply-sa@\nroles/specific per layer\nImpersonation only"]

        GH_OIDC -->|"exchanges via WIF"| WIF_POOL
        WIF_POOL -->|"impersonates"| TF_SA
    end

    subgraph WORKLOADS["Workload Identity (GKE)"]
        KSA["Kubernetes ServiceAccount\nper workload"]
        GSA["GCP ServiceAccount\nper workload\nminimum permissions"]
        WI_BINDING["Workload Identity Binding\nKSA → GSA\nno key export"]

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
    DEV["Developer\n(local)"]
    CI["CI Pipeline\n(GitHub Actions)"]
    APP["Application\n(GKE Pod)"]

    subgraph MGMT["secret-project / KMS"]
        SM["Secret Manager\nversioned secrets\nIAM-controlled access\naudit every read"]
        KMS["Cloud KMS\nCMEK keys\nper-environment keyrings\nannual rotation"]
    end

    subgraph DATA["Data Stores (prod)"]
        SQL["Cloud SQL\nCMEK encrypted"]
        GCS_DATA["Cloud Storage\nCMEK encrypted"]
        BQ["BigQuery\nCMEK encrypted"]
    end

    DEV -->|"impersonate SA\ngcloud secrets access"| SM
    CI -->|"WIF token → SA\nSecret Manager API"| SM
    APP -->|"Workload Identity\nSecret Manager API"| SM

    SM -->|"returns plaintext\nover TLS in-memory"| APP
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
