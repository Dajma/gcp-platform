# Diagram: GKE Architecture

## Cluster Topology

```mermaid
graph TD
    subgraph CONTROL["GKE Control Plane  (Google-managed)"]
        API["kube-apiserver\nprivate endpoint only (prod)\n/28 CIDR — non-overlapping"]
        ETCD["etcd\nCMEK encrypted"]
        SCHED["kube-scheduler\nkube-controller-manager"]
    end

    subgraph NODE_POOLS["Node Pools  (gke-prod project, us-central1)"]
        SYSTEM_POOL["system-pool\ne2-standard-2 × 1 per zone\nTaint: CriticalAddonsOnly\nNo workload scheduling"]
        WORKLOAD_POOL["workload-default\ne2-standard-4 × 2–8 (autoscale)\nWorkload Identity enabled\nShielded nodes"]
        SPOT_POOL["workload-spot\nSPOT e2-standard-4 × 0–4\nFor non-critical / batch\nLabel: spot=true"]
    end

    subgraph NETWORKING["Cluster Networking"]
        VPC_NATIVE["VPC-native (alias IPs)\nNOT routes-based\nPod CIDR: 10.1.0.0/16\nSvc CIDR: 10.2.0.0/20"]
        NET_POL["Network Policies\nDataplane V2 (eBPF)\nDeny-by-default between namespaces"]
        DNS_K8S["kube-dns / Cloud DNS\nPrivate zone peering\nfrom hub VPC"]
    end

    subgraph SECURITY["Cluster Security Controls"]
        WI["Workload Identity\nKSA → GSA\nno node SA key export"]
        BINAUTH["Binary Authorization\nrequire attestation\nall images from Artifact Registry only"]
        PSS["Pod Security Standards\nrestricted profile (prod)\nbaseline profile (nonprod)"]
        RBAC["RBAC\nno cluster-admin for workloads\nper-namespace roles only"]
        AUDIT_K8S["GKE Audit Logs\n→ logging-central project"]
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

    POD->>MDS: Request access token\n(via 169.254.169.254)
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
        APP_MANIFESTS["k8s/\n  apps/\n    app-name/\n      deployment.yaml\n      service.yaml\n      hpa.yaml\n  platform/\n    argocd-apps.yaml"]
    end

    subgraph ARGOCD["ArgoCD  (gke-nonprod / gke-prod)"]
        APP_OF_APPS["App-of-Apps\nroot ArgoCD Application\npoints to k8s/platform/"]
        CHILD_APPS["Child Applications\none per workload\nauto-sync (nonprod)\nmanual-sync (prod)"]

        APP_OF_APPS --> CHILD_APPS
    end

    subgraph CLUSTER["GKE Cluster"]
        DEPLOY["Deployments\nServices\nHPAs\nPDBs"]
    end

    subgraph REGISTRY["Artifact Registry"]
        IMAGES["Signed + attested images\nonly from cicd-platform project\nBinary Auth policy enforced"]
    end

    GIT -->|"ArgoCD polls every 3min\nor webhook on push"| ARGOCD
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
    BUILD["CI Build\n(cicd-platform project)"]
    SIGN["Container image signed\nwith Cloud KMS key\nAttestor: built-by-ci"]
    REG["Artifact Registry\nImage + attestation stored"]
    ADMIT["GKE Admission Controller\n(Binary Authorization)"]
    POL["BinAuth Policy\nrequire attestation from:\n• built-by-ci\n• security-approved (prod)"]
    ALLOW["✅ Pod admitted"]
    DENY["❌ Pod rejected\nEvent logged + alerted"]

    BUILD --> SIGN --> REG
    REG -->|"imagePullPolicy"| ADMIT
    ADMIT --> POL
    POL -->|"attestation present + valid"| ALLOW
    POL -->|"no attestation or invalid"| DENY

    style DENY fill:#FFCDD2,stroke:#C62828
    style ALLOW fill:#DCEDC8,stroke:#558B2F
```
