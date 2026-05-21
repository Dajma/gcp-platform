# Diagram: Network Topology

## Hub-and-Spoke Overview

```mermaid
graph TD
    INTERNET["🌐 Internet"]

    subgraph HUB_PROD["networking-host-prod  (Shared VPC Host)"]
        VPC_PROD["prod-vpc  10.0.0.0/8"]
        NAT_PROD["☁️ Cloud NAT\n(all egress)"]
        DNS_PROD["🔤 Cloud DNS\ninternal.example.com"]
        FW_PROD["🔥 Hierarchical Firewall\nDeny-by-default baseline"]
        LB["⚖️ Cloud Load Balancer\n+ Cloud Armor (WAF)"]

        subgraph SUBNETS_PROD["Subnets  (us-central1)"]
            SN_GKE_PROD["subnet-gke-nodes-prod\n10.0.0.0/20\n+ pods: 10.1.0.0/16\n+ svcs: 10.2.0.0/20"]
            SN_SQL_PROD["subnet-sql-prod\n10.0.16.0/24\nPrivate Service Access"]
            SN_SVC_PROD["subnet-internal-prod\n10.0.32.0/22\nInternal services"]
        end
    end

    subgraph HUB_NONPROD["networking-host-nonprod  (Shared VPC Host)"]
        VPC_NONPROD["nonprod-vpc  10.64.0.0/8"]
        NAT_NONPROD["☁️ Cloud NAT"]
        DNS_NONPROD["🔤 Cloud DNS\ninternal.example.com"]

        subgraph SUBNETS_NONPROD["Subnets  (us-central1)"]
            SN_GKE_NONPROD["subnet-gke-nodes-nonprod\n10.64.0.0/20\n+ pods: 10.65.0.0/16\n+ svcs: 10.66.0.0/20"]
            SN_SQL_NONPROD["subnet-sql-nonprod\n10.64.16.0/24"]
        end
    end

    subgraph SPOKES_PROD["Prod Service Projects  (attached to prod VPC)"]
        GKE_PROD["gke-prod\nPrivate GKE cluster\nno public IPs"]
        APP_PROD["app-{name}-prod\nCloud Run / VMs\nno public IPs"]
    end

    subgraph SPOKES_NONPROD["Nonprod Service Projects  (attached to nonprod VPC)"]
        GKE_NONPROD["gke-nonprod\nPrivate GKE cluster"]
        APP_NONPROD["app-{name}-nonprod"]
    end

    INTERNET -->|"HTTPS only"| LB
    LB --> SN_GKE_PROD
    NAT_PROD -->|"controlled egress"| INTERNET
    VPC_PROD --> NAT_PROD
    VPC_PROD --> DNS_PROD
    VPC_PROD --> FW_PROD

    GKE_PROD -->|"uses subnet"| SN_GKE_PROD
    APP_PROD -->|"uses subnet"| SN_SVC_PROD

    GKE_NONPROD -->|"uses subnet"| SN_GKE_NONPROD
    NAT_NONPROD -->|"controlled egress"| INTERNET

    style HUB_PROD fill:#E3F2FD,stroke:#1565C0
    style HUB_NONPROD fill:#E8F5E9,stroke:#2E7D32
    style SPOKES_PROD fill:#FFF3E0,stroke:#E65100
    style SPOKES_NONPROD fill:#F3E5F5,stroke:#6A1B9A
```

## Subnet Registry

| Subnet | CIDR | Environment | Purpose | Secondary Ranges | PGA |
|---|---|---|---|---|---|
| `subnet-gke-nodes-prod` | `10.0.0.0/20` | prod | GKE nodes | pods `10.1.0.0/16`, svcs `10.2.0.0/20` | ✅ |
| `subnet-sql-prod` | `10.0.16.0/24` | prod | Cloud SQL PSA | — | ✅ |
| `subnet-internal-prod` | `10.0.32.0/22` | prod | Internal services | — | ✅ |
| `subnet-gke-nodes-nonprod` | `10.64.0.0/20` | nonprod | GKE nodes | pods `10.65.0.0/16`, svcs `10.66.0.0/20` | ✅ |
| `subnet-sql-nonprod` | `10.64.16.0/24` | nonprod | Cloud SQL PSA | — | ✅ |

PGA = Private Google Access (all APIs reachable without public IP)

## Firewall Rule Hierarchy

```mermaid
graph TD
    HFW["Hierarchical Firewall Policy\n(org-level)\nDeny all ingress by default\nAllow: IAP → 22,3389\nAllow: health-check ranges"]

    PFW_NET["Project FW — networking-host\nAllow: GKE node comms\nAllow: Cloud NAT hairpin\nAllow: DNS 53"]

    PFW_GKE["Project FW — gke-prod\nAllow: pod-to-pod\nAllow: LB health checks\nAllow: control plane → nodes"]

    PFW_APP["Project FW — app projects\nAllow: internal subnet → app port\nDeny: all else"]

    HFW -->|"inherited by all folders/projects"| PFW_NET
    HFW --> PFW_GKE
    HFW --> PFW_APP

    style HFW fill:#FFCDD2,stroke:#C62828
    style PFW_NET fill:#FFE0B2,stroke:#E65100
    style PFW_GKE fill:#FFE0B2,stroke:#E65100
    style PFW_APP fill:#FFE0B2,stroke:#E65100
```

## Egress Path

```mermaid
sequenceDiagram
    participant POD as Pod / VM
    participant VPC as VPC Router
    participant NAT as Cloud NAT
    participant INT as Internet

    POD->>VPC: outbound packet (no external IP)
    VPC->>NAT: route via 0.0.0.0/0 → NAT gateway
    NAT->>INT: SNAT to static NAT IP
    INT-->>NAT: response
    NAT-->>POD: DNAT back to pod IP

    Note over NAT: LAB: NAT logging disabled (cost)<br/>PROD: NAT logging enabled (audit trail)
```
