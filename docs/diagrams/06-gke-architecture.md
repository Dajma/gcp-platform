# Diagram: GKE Architecture

## Cluster Topology

```mermaid
graph TD
    subgraph CONTROL["GKE Control Plane  (Google-managed)"]
        API["kube-apiserver<br/>private endpoint only (prod)<br/>/28 CIDR — non-overlapping"]
        ETCD["etcd<br/>CMEK encrypted"]
        SCHED["kube-scheduler<br/>kube-controller-manager"]
    end

    subgraph NODE_POOLS["Node Pools  (gke-prod project, us-central1)"]
        SYSTEM_POOL["system-pool<br/>e2-standard-2 × 1 per zone<br/>Taint: CriticalAddonsOnly<br/>No workload scheduling"]
        WORKLOAD_POOL["workload-default<br/>e2-standard-4 × 2–8 (autoscale)<br/>Workload Identity enabled<br/>Shielded nodes"]
        SPOT_POOL["workload-spot<br/>SPOT e2-standard-4 × 0–4<br/>For non-critical / batch<br/>Label: spot=true"]
    end

    subgraph NETWORKING["Cluster Networking"]
        VPC_NATIVE["VPC-native (alias IPs)<br/>NOT routes-based<br/>Pod CIDR: 10.1.0.0/16<br/>Svc CIDR: 10.2.0.0/20"]
        NET_POL["Network Policies<br/>Dataplane V2 (eBPF)<br/>Deny-by-default between namespaces"]
        DNS_K8S["kube-dns / Cloud DNS<br/>Private zone peering<br/>from hub VPC"]
    end

    subgraph SECURITY["Cluster Security Controls"]
        WI["Workload Identity<br/>KSA → GSA<br/>no node SA key export"]
        BINAUTH["Binary Authorization<br/>require attestation<br/>all images from Artifact Registry only"]
        PSS["Pod Security Standards<br/>restricted profile (prod)<br/>baseline profile (nonprod)"]
        RBAC["RBAC<br/>no cluster-admin for workloads<br/>per-namespace roles only"]
        AUDIT_K8S["GKE Audit Logs<br/>→ logging-central project"]
    end

    CONTROL --> NODE_POOLS
    NODE_POOLS --> NETWORKING
    NODE_POOLS --> SECURITY

    style CONTROL fill:#E3F2FD,stroke:#1565C0
    style NODE_POOLS fill:#E8F5E9,stroke:#2E7D32
    style NETWORKING fill:#FFF3E0,stroke:#E65100
    style SECURITY fill:#FFCDD2,stroke:#C62828
```

## Workload Identity Flow

```mermaid
sequenceDiagram
    participant POD as Pod
    participant KSA as Kubernetes SA Token
    participant MDS as GKE Metadata Server
    participant IAM as IAM / STS
    participant GCP as GCP API (e.g. Secret Manager)

    Note over POD,GCP: No JSON key is ever mounted or exported.<br/>Tokens are ephemeral and auto-rotated.

    POD->>MDS: Request access token<br/>(via 169.254.169.254)
    MDS->>KSA: Fetch projected SA token
    KSA-->>MDS: Kubernetes OIDC token (short-lived)
    MDS->>IAM: Exchange K8s token for GCP access token
    IAM->>IAM: Validate KSA annotation matches GSA binding
    IAM-->>MDS: GCP access token (1hr expiry)
    MDS-->>POD: GCP access token

    POD->>GCP: API call with GCP access token
    GCP-->>POD: Response

    Note over IAM: Binding: KSA namespace/name → GSA email<br/>Checked at token exchange time
```

## GitOps with ArgoCD

```mermaid
flowchart LR
    subgraph GIT["Git Repository  (source of truth)"]
        APP_MANIFESTS["k8s/<br/>  apps/<br/>    app-name/<br/>      deployment.yaml<br/>      service.yaml<br/>      hpa.yaml<br/>  platform/<br/>    argocd-apps.yaml"]
    end

    subgraph ARGOCD["ArgoCD  (gke-nonprod / gke-prod)"]
        APP_OF_APPS["App-of-Apps<br/>root ArgoCD Application<br/>points to k8s/platform/"]
        CHILD_APPS["Child Applications<br/>one per workload<br/>auto-sync (nonprod)<br/>manual-sync (prod)"]

        APP_OF_APPS --> CHILD_APPS
    end

    subgraph CLUSTER["GKE Cluster"]
        DEPLOY["Deployments<br/>Services<br/>HPAs<br/>PDBs"]
    end

    subgraph REGISTRY["Artifact Registry"]
        IMAGES["Signed + attested images<br/>only from cicd-platform project<br/>Binary Auth policy enforced"]
    end

    GIT -->|"ArgoCD polls every 3min<br/>or webhook on push"| ARGOCD
    ARGOCD -->|"kubectl apply (server-side)"| CLUSTER
    CLUSTER -->|"pulls image (imagePullPolicy)"| REGISTRY

    style GIT fill:#E3F2FD,stroke:#1565C0
    style ARGOCD fill:#E8F5E9,stroke:#2E7D32
    style CLUSTER fill:#FFF3E0,stroke:#E65100
    style REGISTRY fill:#F3E5F5,stroke:#6A1B9A
```

## Node Pool Strategy

| Pool | Machine Type | Min/Max | Purpose | Spot | Taint |
|---|---|---|---|---|---|
| `system-pool` | `e2-standard-2` | 1–3 | DaemonSets, ArgoCD, CNI | No | `CriticalAddonsOnly=true:NoSchedule` |
| `workload-default` | `e2-standard-4` | 2–8 | General workloads | No | — |
| `workload-spot` | `e2-standard-4` | 0–4 | Batch, CI jobs, stateless | Yes | `spot=true:NoSchedule` |

**Why separate system pool:** Prevents a misbehaving workload (e.g., resource exhaustion) from evicting critical
cluster components like the CNI, monitoring agents, or ArgoCD itself. System pool is never scaled to zero.

## Binary Authorization Policy Flow

```mermaid
flowchart TD
    BUILD["CI Build<br/>(cicd-platform project)"]
    SIGN["Container image signed<br/>with Cloud KMS key<br/>Attestor: built-by-ci"]
    REG["Artifact Registry<br/>Image + attestation stored"]
    ADMIT["GKE Admission Controller<br/>(Binary Authorization)"]
    POL["BinAuth Policy<br/>require attestation from:<br/>• built-by-ci<br/>• security-approved (prod)"]
    ALLOW["✅ Pod admitted"]
    DENY["❌ Pod rejected<br/>Event logged + alerted"]

    BUILD --> SIGN --> REG
    REG -->|"imagePullPolicy"| ADMIT
    ADMIT --> POL
    POL -->|"attestation present + valid"| ALLOW
    POL -->|"no attestation or invalid"| DENY

    style DENY fill:#FFCDD2,stroke:#C62828
    style ALLOW fill:#DCEDC8,stroke:#558B2F
```
