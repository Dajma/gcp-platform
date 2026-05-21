# Diagram: IAM Model

## Identity Hierarchy

```mermaid
graph TD
    subgraph ORG_IAM["Organization-Level IAM"]
        BG1["break-glass-1@domain<br/>roles/owner<br/>⚠️ Alert on every use"]
        BG2["break-glass-2@domain<br/>roles/owner<br/>⚠️ Alert on every use"]
        TF_SA["terraform-org-admin@admin-project<br/>roles/resourcemanager.organizationAdmin<br/>+ 11 specific org-level roles<br/>Impersonation only — no key export"]
    end

    subgraph FOLDER_IAM["Folder-Level IAM  (via groups)"]
        PLAT_ADMIN["group: platform-admins@<br/>Folder: all<br/>roles/resourcemanager.folderAdmin<br/>roles/iam.securityAdmin"]
        SEC_OPS["group: secops@<br/>Folder: security/<br/>roles/securitycenter.admin<br/>roles/logging.admin"]
        NET_ENG["group: network-engineers@<br/>Folder: infrastructure/<br/>roles/compute.networkAdmin"]
        DEV_NONPROD["group: developers@<br/>Folder: nonprod/ only<br/>roles/viewer<br/>roles/logging.viewer"]
    end

    subgraph PROJ_IAM["Project-Level IAM  (workloads)"]
        GKE_SA["gke-workload-{name}@gke-prod<br/>roles/specific-service-role<br/>Workload Identity binding only"]
        APP_SA["app-{name}-sa@app-{name}-prod<br/>roles/specific-service-role<br/>no key export"]
        CICD_SA["terraform-apply-nonprod@cicd-platform<br/>roles/per-layer permissions<br/>WIF impersonation only"]
    end

    TF_SA -->|"creates + manages"| FOLDER_IAM
    TF_SA -->|"creates + manages"| PROJ_IAM
    PLAT_ADMIN -->|"human access"| FOLDER_IAM

    style ORG_IAM fill:#FFCDD2,stroke:#C62828
    style FOLDER_IAM fill:#FFE0B2,stroke:#E65100
    style PROJ_IAM fill:#DCEDC8,stroke:#558B2F
```

## Service Account Strategy

```mermaid
flowchart LR
    subgraph ANTI["❌ Anti-Patterns"]
        A1["Exported JSON key<br/>in repo or CI secret"]
        A2["Shared SA across<br/>multiple workloads"]
        A3["roles/editor or roles/owner<br/>on any SA"]
        A4["Single SA for<br/>all Terraform layers"]
    end

    subgraph CORRECT["✅ Correct Patterns"]
        C1["Impersonation only<br/>(local dev)<br/>WIF only (CI/CD)"]
        C2["One SA per workload<br/>least-privilege roles<br/>annual review"]
        C3["Specific roles only<br/>no primitive roles<br/>audit quarterly"]
        C4["One SA per layer<br/>scoped to that layer's<br/>required permissions"]
    end

    A1 -.- |"replaced by"| C1
    A2 -.- |"replaced by"| C2
    A3 -.- |"replaced by"| C3
    A4 -.- |"replaced by"| C4

    style ANTI fill:#FFCDD2,stroke:#C62828
    style CORRECT fill:#DCEDC8,stroke:#558B2F
```

## Group-Based IAM — Why Groups, Never Individuals

```mermaid
flowchart TD
    subgraph BAD["❌ Direct user bindings  (never do this)"]
        USER1["alice@company.com → roles/compute.admin"]
        USER2["bob@company.com → roles/storage.admin"]
        NOTE1["Problem: offboarding requires scanning<br/>every project's IAM policy.<br/>Easy to miss. Creates ghost permissions."]
    end

    subgraph GOOD["✅ Group-based bindings  (always do this)"]
        GRP1["group: platform-admins@ → roles/compute.admin"]
        GRP2["group: platform-admins@ → roles/storage.admin"]
        GRP_MGMT["Group membership managed<br/>in Cloud Identity / Workspace<br/>One removal = revoked everywhere<br/>Quarterly membership review"]

        GRP1 --> GRP_MGMT
        GRP2 --> GRP_MGMT
    end

    style BAD fill:#FFCDD2,stroke:#C62828
    style GOOD fill:#DCEDC8,stroke:#558B2F
```

## Access Decision Flow

```mermaid
flowchart TD
    REQ["Access Request<br/>(API call with credentials)"]

    ORG_POL["Org Policy check<br/>Does this action violate<br/>an org-level constraint?"]
    IAM_CHK["IAM check<br/>Does the principal have<br/>the required permission?"]
    VPC_SC["VPC Service Controls check<br/>(prod perimeter)<br/>Is the caller inside the perimeter?"]
    AUDIT["Cloud Audit Log<br/>Write audit record<br/>(always, regardless of allow/deny)"]
    ALLOW["✅ Allow"]
    DENY["❌ Deny"]

    REQ --> ORG_POL
    ORG_POL -->|"violates policy"| DENY
    ORG_POL -->|"policy OK"| IAM_CHK
    IAM_CHK -->|"no permission"| DENY
    IAM_CHK -->|"permission granted"| VPC_SC
    VPC_SC -->|"outside perimeter"| DENY
    VPC_SC -->|"inside perimeter"| ALLOW

    ALLOW --> AUDIT
    DENY --> AUDIT

    style DENY fill:#FFCDD2,stroke:#C62828
    style ALLOW fill:#DCEDC8,stroke:#558B2F
    style AUDIT fill:#E1BEE7,stroke:#6A1B9A
```

## Break-Glass Procedure

```mermaid
sequenceDiagram
    participant ENG as On-Call Engineer
    participant BG as Break-Glass Account
    participant SIEM as Cloud Audit Logs
    participant ALERT as PagerDuty / Slack
    participant REVIEW as Security Review

    Note over ENG,REVIEW: Break-glass is for emergencies only.<br/>Normal ops use group-based IAM.

    ENG->>BG: Authenticate (separate MFA device required)
    BG->>SIEM: Login event logged immediately
    SIEM->>ALERT: Alert fires: "Break-glass account used"

    ENG->>BG: Perform emergency action
    BG->>SIEM: Every API call logged (Data Access audit)

    ENG->>BG: Log out immediately after task
    ENG->>REVIEW: File incident report within 24h

    Note over REVIEW: Security team reviews all break-glass<br/>actions within 48h. No exceptions.
```
