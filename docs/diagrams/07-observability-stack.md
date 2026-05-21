# Diagram: Observability Stack

## Log Flow — Centralized Sink Architecture

```mermaid
flowchart LR
    subgraph SOURCES["Log Sources  (all projects)"]
        GKE_LOGS["GKE\ncontainer logs\naudit logs\nnode logs"]
        APP_LOGS["Application\nstructured JSON\nto stdout/stderr"]
        GCP_LOGS["GCP Services\nCloud SQL\nCloud Storage\nCloud LB"]
        AUDIT_LOGS["Cloud Audit Logs\nAdmin Activity\nData Access\nSystem Events"]
    end

    subgraph SINK["Log Router  (org-level aggregated sink)"]
        ROUTER["Cloud Logging Router\nOrg-level sink\nCaptures all projects"]
        EXCL["Exclusion Filters\nDrop: debug logs\nDrop: health check noise\nReviewed quarterly"]
    end

    subgraph DEST["Sink Destinations  (logging-central project)"]
        HOT["Cloud Logging Bucket\n30-day retention\nFast query\nLow cost"]
        BQ["BigQuery Dataset\nPartitioned by day\n90-day expiration\nAd-hoc SQL queries"]
        GCS["Cloud Storage Bucket\nCold archive\n1-year retention\nCMEK encrypted"]
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
        GCP_MON["Cloud Monitoring\nGCP-native metrics\nSLA uptime checks\nCustom metrics API"]
        PROM["Managed Prometheus\n(GKE)\nApp metrics via scrape\nPodMonitor / ServiceMonitor CRDs"]
        CUSTOM["Custom App Metrics\n/metrics endpoint\nHPA v2 custom metrics"]
    end

    subgraph VIZ["Visualization"]
        GRAFANA["Grafana\nDashboards\nAlerts\nCloud Monitoring datasource\n+ Prometheus datasource"]
    end

    subgraph SLO["SLO Framework"]
        SLI["SLIs\n• Availability (uptime)\n• Latency (p99 < threshold)\n• Error rate (5xx / total)"]
        SLO_DEF["SLOs\n• 99.9% availability (prod)\n• p99 latency < 500ms\n• error rate < 0.1%"]
        EB["Error Budget\nConsumed = 1 - actual availability\nBurn rate alerts:\n• Fast burn (1h window, 14× rate)\n• Slow burn (6h window, 3× rate)"]

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
        LBM["Log-Based Metrics\n• Failed IAM auth > 10/5min\n• Privilege escalation\n• Break-glass account used\n• SA key created (forbidden)"]
        MON_POL["Monitoring Policies\n• SLO burn rate (fast + slow)\n• GKE node not ready\n• Pod crash loop\n• Certificate expiry < 30d"]
        DRIFT["Drift Detection\n• Nightly terraform plan\n• exitcode == 2 = drift"]
    end

    subgraph ROUTING["Alert Routing by Severity"]
        P1["P1 — Critical\nSLO fast burn\nSecurity breach\nProduction down"]
        P2["P2 — High\nSLO slow burn\nGKE node failure\nDrift detected"]
        P3["P3 — Low\nCert expiry warning\nCost threshold\nNon-prod issues"]
    end

    subgraph NOTIFY["Notification Channels"]
        PD["PagerDuty\nOn-call rotation\nEscalation policy\n(P1 only)"]
        SLACK["Slack\n#platform-alerts (P1/P2)\n#platform-info (P3)"]
        EMAIL["Email\nBilling alerts\nWeekly summary"]
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

    ALERT --> R1["docs/runbooks/gke-upgrade.md\nTriggered by: node version drift"]
    ALERT --> R2["docs/runbooks/cert-rotation.md\nTriggered by: cert expiry < 30d"]
    ALERT --> R3["docs/runbooks/kms-rotation.md\nTriggered by: annual schedule"]
    ALERT --> R4["docs/runbooks/drift-remediation.md\nTriggered by: drift-detect job"]
    ALERT --> R5["docs/runbooks/scc-triage.md\nTriggered by: SCC HIGH+ finding"]
    ALERT --> R6["docs/runbooks/iam-review.md\nTriggered by: quarterly schedule"]

    style ALERT fill:#FFCDD2,stroke:#C62828
```
