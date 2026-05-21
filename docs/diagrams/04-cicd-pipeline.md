# Diagram: CI/CD Pipeline

## End-to-End Flow

```mermaid
flowchart TD
    DEV["👨‍💻 Developer<br/>pushes to branch"]

    subgraph PR["Pull Request — runs on every push"]
        V["validate<br/>• terraform fmt check<br/>• terraform validate<br/>• tflint (GCP rules)"]
        SS["security-scan<br/>• checkov<br/>• tfsec<br/>• OPA/Conftest policies"]
        PLAN["plan<br/>• terraform plan<br/>• posts diff to PR<br/>• cost estimate"]

        V --> SS --> PLAN
    end

    subgraph MERGE["Merge to main"]
        APPLY_NONPROD["apply-nonprod<br/>• auto-triggered<br/>• WIF → SA impersonation<br/>• applies to dev/staging"]
    end

    subgraph PROD_GATE["Prod Deployment (manual gate)"]
        APPROVAL["👤 Required Approval<br/>• GitHub environment protection<br/>• Named approver required<br/>• Links to issue/ticket"]
        APPLY_PROD["apply-prod<br/>• WIF → prod SA<br/>• applies to prod layer"]
        APPROVAL --> APPLY_PROD
    end

    subgraph NIGHTLY["Nightly Jobs (cron)"]
        DRIFT["drift-detect<br/>• terraform plan -detailed-exitcode<br/>• alerts on any diff<br/>• posts to Slack/PagerDuty"]
        DOCGEN["docs-gen<br/>• terraform-docs<br/>• opens auto-PR if README changed"]
    end

    DEV --> PR
    PR -->|"all checks pass + approved"| MERGE
    MERGE --> PROD_GATE
    PROD_GATE -->|"after nonprod validated"| APPLY_PROD

    style PR fill:#E3F2FD,stroke:#1565C0
    style MERGE fill:#E8F5E9,stroke:#2E7D32
    style PROD_GATE fill:#FFF3E0,stroke:#E65100
    style NIGHTLY fill:#F3E5F5,stroke:#6A1B9A
```

## Workload Identity Federation — Credential Flow

```mermaid
sequenceDiagram
    participant GH as GitHub Actions Runner
    participant GHOIDC as GitHub OIDC Endpoint
    participant WIF as GCP WIF Identity Pool
    participant STS as GCP Security Token Service
    participant SA as Terraform Service Account
    participant GCP as GCP APIs

    GH->>GHOIDC: Request OIDC token (job context)
    GHOIDC-->>GH: JWT (iss: token.actions.githubusercontent.com)

    Note over GH,GHOIDC: Token contains: repo, workflow, ref, sha

    GH->>WIF: Exchange JWT for GCP credential
    WIF->>WIF: Validate JWT signature + claims
    Note over WIF: Checks: repo == allowed repo<br/>ref == allowed branch

    WIF->>STS: Issue federated token
    STS-->>GH: Short-lived federated credential (1hr)

    GH->>SA: Impersonate SA using federated credential
    SA-->>GH: Short-lived SA access token (1hr)

    GH->>GCP: terraform apply (with SA token)
    GCP-->>GH: API responses

    Note over GH,GCP: Zero static credentials ever stored.<br/>All tokens expire in ≤ 1 hour.
```

## Job Definitions

```mermaid
graph LR
    subgraph JOBS["GitHub Actions Jobs"]
        J1["validate<br/>Trigger: every push<br/>Blocks: security-scan<br/>Fails on: fmt diff, validate error, tflint"]
        J2["security-scan<br/>Trigger: every push<br/>Blocks: plan<br/>Fails on: HIGH/CRITICAL checkov/tfsec findings"]
        J3["plan<br/>Trigger: every push<br/>Blocks: merge<br/>Outputs: plan summary as PR comment"]
        J4["apply-nonprod<br/>Trigger: merge to main<br/>Auto: yes<br/>Env: nonprod WIF provider"]
        J5["apply-prod<br/>Trigger: merge to main<br/>Auto: NO — requires approval<br/>Env: prod WIF provider"]
        J6["drift-detect<br/>Trigger: nightly 02:00 UTC<br/>Alerts: if exitcode == 2"]
        J7["docs-gen<br/>Trigger: nightly 03:00 UTC<br/>Opens: auto-PR for README updates"]
    end

    J1 --> J2 --> J3
    J3 --> J4
    J4 --> J5

    style J5 fill:#FFCDD2,stroke:#C62828
    style J4 fill:#DCEDC8,stroke:#558B2F
```

## Environment Separation

| Environment | WIF Pool | Terraform SA | Apply Trigger | Approval Required |
|---|---|---|---|---|
| nonprod | `wif-pool-nonprod` | `terraform-apply-nonprod@...` | Auto on merge to `main` | No |
| prod | `wif-pool-prod` | `terraform-apply-prod@...` | Manual gate | Yes — named approver |

**Why separate WIF pools per environment:**
A compromised nonprod pipeline cannot forge a prod credential even if it knows the prod SA email.
The WIF pool validates which repo + branch the token was issued for — a nonprod pool will never
issue credentials bound to the prod SA. See ADR-001 for related state isolation rationale.
