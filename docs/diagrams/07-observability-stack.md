# Diagram: Observability Stack

## Log Flow — Centralized Sink Architecture

```mermaid
flowchart LR
    subgraph SOURCES["Log Sources  (all projects)"]
        GKE_LOGS["GKE<br/>container logs<br/>audit logs<br/>node logs"]
        APP_LOGS["Application<br/>structured JSON<br/>to stdout/stderr"]
        GCP_LOGS["GCP Services<br/>Cloud SQL<br/>Cloud Storage<br/>Cloud LB"]
        AUDIT_LOGS["Cloud Audit Logs<br/>Admin Activity<br/>Data Access<br/>System Events"]
    end

    subgraph SINK["Log Router  (org-level aggregated sink)"]
        ROUTER["Cloud Logging Router<br/>Org-level sink<br/>Captures all projects"]
        EXCL["Exclusion Filters<br/>Drop: debug logs<br/>Drop: health check noise<br/>Reviewed quarterly"]
    end

    subgraph DEST["Sink Destinations  (logging-central project)"]
        HOT["Cloud Logging Bucket<br/>30-day retention<br/>Fast query<br/>Low cost"]
        BQ["BigQuery Dataset<br/>Partitioned by day<br/>90-day expiration<br/>Ad-hoc SQL queries"]
        GCS["Cloud Storage Bucket<br/>Cold archive<br/>1-year retention<br/>CMEK encrypted"]
    end

    SOURCES --> ROUTER
    ROUTER --> EXCL
    EXCL --> HOT
    EXCL --> BQ
    EXCL --> GCS

    style SOURCES fill:#E3F2FD,stroke:#1565C0
    style SINK fill:#FFF9C4,stroke:#F9A825
    style DEST fill:#E8F5E9,stroke:#2E7D32
```

## Metrics and Monitoring Stack

```mermaid
graph TD
    subgraph METRICS["Metrics Collection"]
        GCP_MON["Cloud Monitoring<br/>GCP-native metrics<br/>SLA uptime checks<br/>Custom metrics API"]
        PROM["Managed Prometheus<br/>(GKE)<br/>App metrics via scrape<br/>PodMonitor / ServiceMonitor CRDs"]
        CUSTOM["Custom App Metrics<br/>/metrics endpoint<br/>HPA v2 custom metrics"]
    end

    subgraph VIZ["Visualization"]
        GRAFANA["Grafana<br/>Dashboards<br/>Alerts<br/>Cloud Monitoring datasource<br/>+ Prometheus datasource"]
    end

    subgraph SLO["SLO Framework"]
        SLI["SLIs<br/>• Availability (uptime)<br/>• Latency (p99 < threshold)<br/>• Error rate (5xx / total)"]
        SLO_DEF["SLOs<br/>• 99.9% availability (prod)<br/>• p99 latency < 500ms<br/>• error rate < 0.1%"]
        EB["Error Budget<br/>Consumed = 1 - actual availability<br/>Burn rate alerts:<br/>• Fast burn (1h window, 14× rate)<br/>• Slow burn (6h window, 3× rate)"]

        SLI --> SLO_DEF --> EB
    end

    GCP_MON --> GRAFANA
    PROM --> GRAFANA
    GRAFANA --> SLO

    style METRICS fill:#E3F2FD,stroke:#1565C0
    style VIZ fill:#E8F5E9,stroke:#2E7D32
    style SLO fill:#FFE0B2,stroke:#E65100
```

## Alerting Pipeline

```mermaid
flowchart LR
    subgraph TRIGGERS["Alert Triggers"]
        LBM["Log-Based Metrics<br/>• Failed IAM auth > 10/5min<br/>• Privilege escalation<br/>• Break-glass account used<br/>• SA key created (forbidden)"]
        MON_POL["Monitoring Policies<br/>• SLO burn rate (fast + slow)<br/>• GKE node not ready<br/>• Pod crash loop<br/>• Certificate expiry < 30d"]
        DRIFT["Drift Detection<br/>• Nightly terraform plan<br/>• exitcode == 2 = drift"]
    end

    subgraph ROUTING["Alert Routing by Severity"]
        P1["P1 — Critical<br/>SLO fast burn<br/>Security breach<br/>Production down"]
        P2["P2 — High<br/>SLO slow burn<br/>GKE node failure<br/>Drift detected"]
        P3["P3 — Low<br/>Cert expiry warning<br/>Cost threshold<br/>Non-prod issues"]
    end

    subgraph NOTIFY["Notification Channels"]
        PD["PagerDuty<br/>On-call rotation<br/>Escalation policy<br/>(P1 only)"]
        SLACK["Slack<br/>#platform-alerts (P1/P2)<br/>#platform-info (P3)"]
        EMAIL["Email<br/>Billing alerts<br/>Weekly summary"]
    end

    TRIGGERS --> ROUTING
    P1 --> PD
    P1 --> SLACK
    P2 --> SLACK
    P3 --> EMAIL

    style P1 fill:#FFCDD2,stroke:#C62828
    style P2 fill:#FFE0B2,stroke:#E65100
    style P3 fill:#FFF9C4,stroke:#F9A825
```

## SLO Error Budget Burn Rate Alerts

```mermaid
gantt
    title Error Budget Consumption — 30-day rolling window
    dateFormat  YYYY-MM-DD
    axisFormat  Day %d

    section Normal (budget intact)
    Healthy zone           :done,    2026-05-01, 15d

    section Warning (P3 alert)
    Budget 50% consumed    :active,  2026-05-16, 7d

    section Critical (P2 alert — slow burn)
    Budget 75% consumed    :crit,    2026-05-23, 5d

    section Freeze (P1 alert — fast burn)
    Budget 90%+ in < 1hr   :crit,    2026-05-28, 3d
```

## Log-Based Security Metrics (Phase 4)

| Metric Name | Log Filter | Alert Threshold | Severity |
|---|---|---|---|
| `iam_auth_failures` | `protoPayload.status.code=7` | > 10 in 5min | P2 |
| `privilege_escalation` | `protoPayload.methodName=~"setIamPolicy"` | Any | P1 |
| `break_glass_used` | `protoPayload.authenticationInfo.principalEmail=~"break-glass"` | Any | P1 |
| `sa_key_created` | `protoPayload.methodName="iam.serviceAccounts.keys.create"` | Any | P2 |
| `org_policy_changed` | `protoPayload.methodName=~"orgpolicies"` | Any | P1 |
| `gcs_public_access` | `protoPayload.methodName=~"storage.*" AND protoPayload.resourceName=~"allUsers"` | Any | P1 |

## Runbook Dependency Map

```mermaid
graph LR
    ALERT["Alert fires"]

    ALERT --> R1["docs/runbooks/gke-upgrade.md<br/>Triggered by: node version drift"]
    ALERT --> R2["docs/runbooks/cert-rotation.md<br/>Triggered by: cert expiry < 30d"]
    ALERT --> R3["docs/runbooks/kms-rotation.md<br/>Triggered by: annual schedule"]
    ALERT --> R4["docs/runbooks/drift-remediation.md<br/>Triggered by: drift-detect job"]
    ALERT --> R5["docs/runbooks/scc-triage.md<br/>Triggered by: SCC HIGH+ finding"]
    ALERT --> R6["docs/runbooks/iam-review.md<br/>Triggered by: quarterly schedule"]

    style ALERT fill:#FFCDD2,stroke:#C62828
```
