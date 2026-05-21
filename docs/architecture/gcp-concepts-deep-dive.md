# GCP Concepts Deep Dive

A principal-engineer-level explanation of every key concept in this platform's design.
Written to answer "what is this, why does it exist, and how does it work?"

---

## 1. Folders — Purpose and Problems They Solve

### What they are
Folders are an **organisational grouping layer** in the GCP resource hierarchy, sitting between
the Organisation and Projects:

```
Organisation
└── Folder (e.g. prod/)
    └── Folder (e.g. prod/workloads/)
        └── Project
            └── Resources (VMs, GKE clusters, buckets, etc.)
```

Folders have no compute or storage resources themselves. They are purely administrative.

### What problems they solve

**1. IAM inheritance at scale**
IAM bindings set on a folder are automatically inherited by every project inside it.
Without folders, you would need to set IAM on every project individually.
With 50 projects and 10 teams, that's 500 IAM updates every time someone joins or leaves.
With folders, you bind the group once at the folder level and every project inherits it.

```
Folder: prod/
  IAM: group:platform-admins@ → roles/compute.admin
  ↓ inherited automatically by:
    Project: gke-prod
    Project: app-payments-prod
    Project: app-orders-prod
```

**2. Org Policy scope**
Org Policies (constraints on what GCP resources can do) can be applied at folder level.
Example: apply `compute.requireShieldedVm` to the `prod/` folder only.
Sandbox projects are excluded, so engineers can experiment freely without the policy blocking them.

**3. Billing and cost visibility**
You can filter billing reports by folder. This gives you cost-per-environment
(`prod/` vs `nonprod/`) and cost-per-concern (`security/` vs `shared-services/`) without
needing to manually tag every resource query.

**4. Blast radius containment**
A security incident in `nonprod/` cannot affect `prod/` by policy — separate VPCs,
separate IAM scope, separate org policies can be enforced per folder.

**5. Trust boundary enforcement**
VPC Service Control perimeters (explained later) align with folder/project boundaries.
You cannot draw a perimeter around a folder, but you can draw it around all projects inside a folder.

### Our folder structure and why

```
Organisation
├── infrastructure/   → networking host projects only. High trust. Managed by platform team.
├── security/         → logging, KMS, SCC. Highest trust. No workload code ever lands here.
├── shared-services/  → CI/CD, Artifact Registry. Medium-high trust.
├── prod/             → production workloads. Strict org policies applied.
├── nonprod/          → dev/staging workloads. Looser policies, faster iteration.
└── sandbox/          → unrestricted experimentation. Separate billing budget. Auto-cleanup.
```

The folder a project lives in determines what org policies apply to it, what IAM groups
inherit into it, and what network it can attach to.

---

## 2. Projects — Isolation Model

### What a project is
A project is GCP's fundamental unit of **resource isolation, billing, and API enablement**.
Every GCP resource (VM, bucket, GKE cluster, VPC) lives in exactly one project.

### Isolation properties

| Isolation type | Within a project | Across projects |
|---|---|---|
| IAM | Shared by default | No access by default — must be explicitly granted |
| Networking | VMs can communicate on the same VPC | No network connectivity by default |
| Billing | Consolidated on one account | Can split across accounts |
| API quotas | Shared quota pool | Separate quota pool per project |
| Audit logs | Aggregated to project | Separate log streams (centralized via sinks) |
| Blast radius | A `terraform destroy` can wipe all resources | Cannot affect other projects |

### Are VPCs restricted to a single project?

**By default, yes.** A VPC is created in a project and only resources in that project can use it.

However, there are two mechanisms to share networks across projects:

1. **Shared VPC** — the primary mechanism used in this design (explained in section 7)
2. **VPC Peering** — connects two VPCs via Google's internal network (no traffic leaves Google)

VPC Peering vs Shared VPC:

| | Shared VPC | VPC Peering |
|---|---|---|
| Who manages subnets | Host project only | Each project manages its own |
| IP overlap allowed | No | No |
| Transitive routing | Yes (hub-and-spoke) | No — peering is not transitive |
| IAM control | Centralised in host project | Per-project |
| Recommended for | Enterprise, multi-project platforms | Simpler two-project connections |

Subnets are regional resources — they exist within a project's VPC and in a specific GCP region.
They are not inherently restricted to one project, but without Shared VPC, only the owning project
can place resources in them.

---

## 3. GCP Networking Fundamentals

### VPCs in GCP vs traditional networking

GCP VPCs are **global** — a single VPC spans all regions. This is different from AWS where a VPC
is region-scoped. You create subnets per-region within a single global VPC.

```
VPC: prod-vpc  (global)
├── Subnet: subnet-gke-nodes-prod  (us-central1)  10.0.0.0/20
├── Subnet: subnet-sql-prod         (us-central1)  10.0.16.0/24
└── Subnet: subnet-gke-nodes-prod  (europe-west1)  10.16.0.0/20  ← same VPC, different region
```

Resources in `us-central1` can communicate with resources in `europe-west1` on the same VPC
without any VPN or peering — traffic routes internally on Google's network.

### Key GCP networking components

**VPC (Virtual Private Cloud)**
Software-defined network. Defines the IP space and routing rules. Global.
Resources attach to subnets within a VPC.

**Subnets**
Regional IP ranges within a VPC. VMs and GKE nodes get IPs from subnets.
Secondary IP ranges on a subnet are used for GKE pod and service IPs (VPC-native clusters).

**Routes**
Tell GCP where to forward packets. Default route: `0.0.0.0/0 → default internet gateway`.
For private-only workloads, the default route is removed and replaced with a Cloud NAT route.

**Cloud NAT (Network Address Translation)**
Allows VMs with no external IP to reach the internet for outbound connections (e.g. pulling packages).
Inbound connections from the internet are not allowed — NAT is outbound only.
All VMs share the NAT's external IP(s) — this is how you maintain a stable egress IP for allowlisting.

**Firewall rules**
Stateful rules that control what traffic is allowed to/from VMs and GKE nodes.
GCP firewall rules are applied at the VM/instance level (via network tags or service accounts),
not at the subnet level like AWS Security Groups.

**Hierarchical Firewall Policies**
Org- or folder-level firewall rules that apply to all projects below them in the hierarchy.
Applied before project-level rules. Used to enforce baseline deny-all at the org level.

**Private Google Access**
When enabled on a subnet, VMs with no external IP can still reach Google APIs
(Cloud Storage, BigQuery, Secret Manager, etc.) via Google's internal network.
Without PGA, a private VM has no way to talk to GCP services.

**Cloud DNS**
GCP's managed DNS service. Can create private zones (only resolvable within your VPC),
public zones, and forwarding zones that forward queries to on-prem DNS servers.

---

## 4. Our Proposed Network Design

### Why hub-and-spoke?

The alternative is flat networking: every project gets its own VPC, and you VPC-peer them
into a mesh. This breaks down at scale because:
- VPC Peering is not transitive: if A peers with B and B peers with C, A cannot talk to C
- Managing N×(N-1)/2 peering connections for N projects is operationally unsustainable
- No centralised egress — each project needs its own NAT, own DNS, own firewall rules

Hub-and-spoke solves this: one central VPC (the hub) connects to all spoke projects.
All routing, DNS, NAT, and firewall baselines are managed in one place.

### Our design

```
                     ┌─────────────────────────────────────┐
                     │   networking-host-prod               │
                     │   (Shared VPC Host Project)          │
                     │                                      │
  Internet ──NAT──► │   prod-vpc  10.0.0.0/8               │
                     │   Cloud NAT (all egress)             │
                     │   Cloud DNS (internal zones)         │
                     │   Hierarchical FW (baseline deny)    │
                     │                                      │
                     │   Subnets:                           │
                     │   ├── subnet-gke-nodes-prod          │
                     │   ├── subnet-sql-prod                │
                     │   └── subnet-internal-prod          │
                     └──────────┬──────────────────────────┘
                                │ Shared VPC attachment
                    ┌───────────┼───────────┐
                    │           │           │
              ┌─────┴────┐ ┌────┴─────┐ ┌──┴───────────┐
              │ gke-prod  │ │app-X-prod│ │security-proj │
              │(service   │ │(service  │ │(service      │
              │ project)  │ │ project) │ │ project)     │
              └───────────┘ └──────────┘ └──────────────┘
```

**Key properties:**
- All prod workload projects attach to `prod-vpc` as service projects
- None of the service projects have their own VPC — they use subnets from the host project
- All internet egress from all service projects routes through the hub's Cloud NAT
- All DNS resolution uses the hub's Cloud DNS
- Firewall rules are centrally managed in the hub; service projects add workload-specific rules
- An identical second hub exists for nonprod (`networking-host-nonprod`, `nonprod-vpc`)
- The two hubs never connect — prod and nonprod are isolated at the network level

---

## 5. Security Command Center (SCC)

### What it does

SCC is GCP's native **cloud security posture management (CSPM) and threat detection** platform.
It runs continuously without you deploying any agents or infrastructure.

Think of it as an always-on security scanner that knows everything about your GCP environment.

### Two categories of findings

**Vulnerabilities (misconfigurations)**
SCC scans your GCP resources and flags when they violate security best practices:
- GCS bucket with public access enabled
- VM with an external IP and firewall rule open to `0.0.0.0/0`
- Service account with `roles/owner` binding
- Cloud SQL instance with no SSL required
- GKE cluster with legacy authentication enabled

These are not attacks — they are configuration mistakes that create attack surface.

**Threats (active attacks or suspicious activity)**
SCC's threat detection analyses your Cloud Audit Logs and network flows in real time:
- Crypto-mining malware detected on a VM (anomalous CPU + network patterns)
- Unusual outbound data transfer (potential exfiltration)
- Brute-force SSH attempts from external IPs
- A service account suddenly calling APIs it has never called before
- Privilege escalation: a principal granting themselves new IAM roles

### Tiers

| Tier | What you get | Cost |
|---|---|---|
| Standard | Vulnerability scanning (misconfigs), asset inventory | Free |
| Premium | + Threat detection (Event Threat Detection, Container Threat Detection), compliance reports, attack path simulation | ~$0.06/asset/month |

**In this lab:** Standard tier. Premium threat detection is documented but not enabled (cost).

### Does it need agents?

For **VM-level threat detection** (Premium): yes, the Security Command Center agent runs
as a DaemonSet on GKE or as a VM agent. It monitors for malware, rootkits, and kernel-level threats.

For **everything else** (misconfiguration scanning, audit log analysis, network threat detection):
**no agents** — SCC reads your Cloud Audit Logs and GCP resource metadata directly via APIs.
It is entirely agentless for most of its functionality.

---

## 6. Cloud Armor, WAF, and DDoS Protection

### The problem

Your application is exposed on a public HTTPS load balancer. Without protection:
- Layer 7 attacks (SQL injection, XSS, Log4Shell exploits) hit your app directly
- Layer 3/4 volumetric DDoS attacks can saturate your load balancer and exhaust quotas
- Scrapers and credential-stuffing bots can abuse your APIs at scale

### Cloud Armor

Cloud Armor is GCP's **Web Application Firewall (WAF) and DDoS mitigation** service.
It sits in front of the Google Cloud HTTP(S) Load Balancer — before traffic reaches your backend.

```
Internet → Cloud Armor → Cloud LB → Backend (GKE, Cloud Run, etc.)
              ↑
         All traffic inspected here
         Bad traffic dropped before reaching your app
```

**What it does:**

**DDoS protection (always-on, free)**
Google's network absorbs volumetric Layer 3 and Layer 4 attacks (SYN floods, UDP floods, ICMP floods)
at the edge — your backend never sees them. This protection is automatic and free for all HTTPS LBs.
Google's network is large enough to absorb even the largest known DDoS attacks.

**WAF rules (Cloud Armor Managed Rules)**
Pre-built rules that detect and block common attacks:
- OWASP Top 10: SQL injection, XSS, command injection, path traversal
- Log4Shell / Log4j exploits
- Apache Struts attacks
- Scanner detection (blocks automated vulnerability scanners)

These are maintained by Google's security team and updated automatically.

**Custom rules**
You write rules in a CEL-like expression language:
```
# Block requests from specific countries
origin.region_code == 'CN' || origin.region_code == 'RU'

# Rate limit: max 100 requests per minute per IP
rate_based_ban(ip_address, 100, 60)

# Block specific paths
request.path.matches('/admin/.*')
```

**Adaptive Protection (AI/ML)**
Cloud Armor learns your traffic baseline and automatically detects anomalies (burst traffic,
unusual geographic patterns, abnormal request rates). It can suggest rules and optionally
apply them automatically.

**Cost:** Per-policy, per-rule, and per-million requests processed. In lab: minimal policy.

---

## 7. OS Login

### The problem without OS Login

Traditionally, SSH access to a Linux VM requires either:
1. A password (terrible for automated environments)
2. An SSH key pair — you put the public key on the VM at creation time

The problem: SSH keys are static credentials. If you have 100 engineers and 500 VMs:
- How do you revoke access when someone leaves? You'd need to remove their key from every VM.
- How do you audit who logged in? SSH logs are local to the VM — easy to tamper with.
- What if someone copies their private key? You have no visibility.

### What OS Login does

OS Login links SSH access to **GCP IAM**. Instead of putting a key on a VM at creation time,
you grant an IAM role, and GCP dynamically manages authorised keys.

```
Engineer wants SSH access to a VM:
  1. Admin grants: roles/compute.osLogin on the project (or VM)
  2. Engineer registers their SSH public key once: gcloud compute os-login ssh-keys add
  3. Engineer SSHs: gcloud compute ssh my-vm
  4. GCP checks IAM: does this user have roles/compute.osLogin?
  5. Yes → generates an ephemeral OS user, grants access
  6. All of this is logged in Cloud Audit Logs
```

**Benefits:**
- Revoking access = removing the IAM binding, instantly applies everywhere
- Two-factor authentication: can enforce 2FA on the GCP account used for OS Login
- Full audit trail in Cloud Audit Logs — who logged in, from where, when
- No long-lived SSH keys on VMs — keys are ephemeral and managed by GCP

**Org Policy enforcement:**
`compute.requireOsLogin = true` — prevents VMs from being created with SSH keys in metadata.
This is enforced via org policy in Phase 1, so no engineer can accidentally bypass it.

---

## 8. Private Service Access (PSA)

### The problem

You want Cloud SQL (a fully-managed Google service) to be accessible from your GKE pods.
Cloud SQL is managed by Google — it runs in Google's infrastructure, not your VPC.

If you connect to it over the public internet:
- Traffic leaves Google's network, traverses the internet, comes back
- The Cloud SQL IP is a public IP — it's exposed to the internet (even if firewalled)
- Every connection requires SSL/TLS termination at a public endpoint

### What PSA does

PSA creates a **private peering connection** between your VPC and Google's service producer VPC
(where managed services like Cloud SQL, Memorystore, Cloud Filestore live).

```
Your VPC                    Google's Service Producer VPC
┌────────────────┐          ┌─────────────────────────────┐
│                │◄─ PSA ──►│  Cloud SQL instance          │
│ subnet-sql-prod│  peering │  private IP: 10.0.16.5       │
│ 10.0.16.0/24  │          │  (allocated from your range) │
└────────────────┘          └─────────────────────────────┘
```

The Cloud SQL instance gets a **private IP from your subnet range**. Your pods connect to
`10.0.16.5` (a private IP) — traffic never leaves Google's network, never hits the internet,
and there is no public IP on the Cloud SQL instance at all.

**Setup:**
1. Allocate a private IP range in your VPC for Google services: `gcloud compute addresses create`
2. Create a private services connection: `gcloud services vpc-peerings connect`
3. Cloud SQL, Memorystore, and other services deployed in that VPC now get IPs from your range

**What PSA does NOT do:**
PSA peering is not transitive. If your VPC peers with Google's service VPC via PSA,
and your VPC also peers with another VPC, that second VPC cannot reach Google services
through your PSA connection. Each VPC needs its own PSA setup.

---

## 9. Connecting VPCs Across Projects or Accounts

There are four mechanisms. Each solves a different problem:

### Option 1: Shared VPC (our primary mechanism)

One project owns the VPC (host project). Other projects (service projects) are attached and
use subnets from the host VPC. Detailed in section 10.

**Use when:** You want centralised network management across many projects in the same org.

### Option 2: VPC Peering

Two separate VPCs (in any project, any org) exchange routes via Google's internal network.
Traffic stays on Google's backbone — no VPN, no public IPs.

```
Project A: vpc-a  10.0.0.0/8
    ↕ VPC Peering (internal)
Project B: vpc-b  10.64.0.0/8
```

**Limitations:**
- **Not transitive**: A↔B and B↔C does not mean A↔C
- Both VPCs must have non-overlapping IP ranges
- No Shared VPC features (e.g. centralized firewall management)
- Maximum 25 peerings per VPC

**Use when:** Connecting two specific VPCs, cross-org connectivity, simpler setups.

### Option 3: Cloud VPN

IPsec tunnels between your GCP VPC and an on-premises network (or another cloud).
Traffic is encrypted. Capacity: ~3 Gbps per tunnel (HA VPN: 3 Gbps × 2 tunnels).

```
GCP VPC  ←→  Cloud VPN Gateway  ←→  [Internet/Dedicated]  ←→  On-prem router
```

**Use when:** Connecting GCP to on-premises or to other cloud providers.

### Option 4: Cloud Interconnect

Dedicated physical fiber connection between your data centre and Google's network.
Bypasses the public internet entirely. Options: 10 Gbps or 100 Gbps circuits.
Partner Interconnect: 50 Mbps–10 Gbps via a connectivity partner.

**Use when:** High-bandwidth, low-latency, private connectivity to on-premises.
Significant cost and lead time — not relevant for this lab.

---

## 10. Host Project and Shared VPC

### The host project

In Shared VPC, the **host project** is the project that owns the VPC — it contains:
- The VPC itself
- All subnets
- Firewall rules
- Cloud NAT
- Cloud DNS

The host project is managed entirely by the network/platform team. Application teams
have no IAM access to it — they cannot create or modify subnets, firewall rules, or routes.

In our design: `networking-host-prod` (for prod) and `networking-host-nonprod` (for nonprod).

### Service projects

Service projects are projects that are **attached** to the host project. Resources in a service
project (GKE nodes, VMs, Cloud SQL) can use subnets from the host project's VPC, but:
- They cannot create subnets
- They cannot modify firewall rules
- They cannot see the VPC configuration
- They only get access to specific subnets, granted by the network admin

```
Host project: networking-host-prod
└── VPC: prod-vpc
    ├── subnet-gke-nodes-prod  → granted to: gke-prod (service project)
    ├── subnet-sql-prod        → granted to: app-payments-prod (service project)
    └── subnet-internal-prod   → granted to: security-project (service project)

Service project: gke-prod
└── GKE cluster (nodes get IPs from subnet-gke-nodes-prod in host project)
```

### Why this matters

Without Shared VPC: every project has its own VPC. You need VPC peering between them all,
and each project manages its own firewall rules, NAT, and DNS — a configuration management nightmare.

With Shared VPC: one network team manages one VPC. All projects share it with controlled,
per-subnet access. A developer in `gke-prod` cannot touch networking — they get the subnet
they're allocated and nothing else.

**Org policy:** Only org admins can enable Shared VPC. This prevents a rogue project from
creating its own Shared VPC and attaching to production subnets.

---

## 11. Hub-and-Spoke Design Explained

### Architecture

```
                   [Internet]
                       │ HTTPS only
                       ▼
              [Cloud Armor / Cloud LB]
                       │
                       ▼
    ┌─────────────────────────────────────────┐
    │  HUB: networking-host-prod              │
    │                                         │
    │  prod-vpc  10.0.0.0/8                   │
    │  ├── Cloud NAT (all outbound egress)    │
    │  ├── Cloud DNS (private zones)          │
    │  ├── Hierarchical FW (deny-all base)    │
    │  └── Subnets (gke, sql, internal)       │
    │                                         │
    └──────┬──────────┬──────────┬────────────┘
           │          │          │
    Shared VPC attachment (per subnet)
           │          │          │
    ┌──────┴──┐ ┌──────┴──┐ ┌───┴──────────┐
    │ gke-prod│ │app-X-prod│ │security-proj │
    │ SPOKE   │ │ SPOKE    │ │   SPOKE      │
    └─────────┘ └──────────┘ └──────────────┘
```

### How traffic flows

**Pod to internet (egress):**
```
Pod (10.0.0.5) → VPC Router → Default route: 0.0.0.0/0 → Cloud NAT → Internet
```
The pod has no external IP. The NAT translates its private IP to the NAT's external IP.
All spoke projects share the same NAT — centralised egress, one place to manage egress IPs.

**Pod to Cloud SQL (private):**
```
Pod (10.0.0.5) → VPC Router → subnet-sql-prod → PSA peering → Cloud SQL (10.0.16.5)
```
Never leaves Google's network. No internet involved.

**External user to application:**
```
User → Internet → Cloud Armor → Cloud LB (public IP) → GKE Service (internal IP) → Pod
```
The LB is the only resource with a public IP. Everything behind it is private.

**Pod to Secret Manager (private Google access):**
```
Pod (10.0.0.5) → Private Google Access route → Google APIs (secretmanager.googleapis.com)
```
Private Google Access allows pods to reach Google APIs without a public IP or internet route.

### Why two hubs (prod + nonprod)?

A developer's nonprod credentials should never be able to route traffic into the prod network.
With two separate VPCs:
- A misconfigured firewall in nonprod cannot accidentally expose prod resources
- A compromised nonprod service account cannot reach prod databases
- The blast radius of a nonprod incident is bounded to nonprod

---

## 12. Binary Authorization and Container Image Attestation

### The supply chain problem

Your GKE cluster can pull images from anywhere — Docker Hub, a public registry, a compromised
internal registry. An attacker who compromises your CI pipeline could push a malicious image
that gets deployed to production without anyone noticing.

Binary Authorization solves this with a **cryptographic admission control** gate.

### How it works

**Step 1: Build and sign in CI**

When your CI pipeline builds an image:
```
CI builds image → pushed to Artifact Registry → CI signs the image digest with a Cloud KMS key
```

The signature (called an **attestation**) is stored alongside the image in Artifact Registry:
```
Image: us-central1-docker.pkg.dev/cicd/app:sha256-abc123
Attestation: signed by key projects/security-proj/keyRings/binauth/cryptoKeys/ci-signer
  "this image was built by our verified CI pipeline"
```

The attestation proves:
- This specific image (by its SHA256 digest) was processed by our CI
- The CI pipeline had access to the Cloud KMS signing key
- The image has not been tampered with (any change to the image changes the digest, invalidating the attestation)

**Step 2: Policy enforced at GKE admission**

Binary Authorization is a GKE admission controller (a webhook that intercepts every pod creation).
When a pod is admitted:

```
kubectl apply (or ArgoCD) → kube-apiserver → BinAuth webhook
                                                    ↓
                               Check: does this image have a valid attestation?
                               Check: was it signed by the approved attestor?
                                    ↓               ↓
                               YES → allow      NO → reject (pod never starts)
```

**In prod:** both `built-by-ci` AND `security-approved` attestations required.
**In nonprod:** `built-by-ci` attestation required.
**In sandbox:** policy is set to `ALLOW_ALL` (for experimentation).

### What this prevents

- A developer doing `kubectl apply` with a random Docker Hub image in production → **blocked**
- An attacker who compromises the registry and swaps an image → **blocked** (digest changes, attestation invalid)
- An image built outside the approved CI pipeline → **blocked** (no attestation from the approved KMS key)
- A developer accidentally deploying a dev build to prod → **blocked** (prod requires security-approved attestation)

### Attestors

An attestor is the entity whose signature is required. You define attestors in Binary Authorization:
```
Attestor: built-by-ci
  → requires signature from KMS key: projects/cicd-platform/keyRings/binauth/cryptoKeys/ci-signer

Attestor: security-approved  (prod only)
  → requires signature from KMS key: projects/security-project/keyRings/binauth/cryptoKeys/sec-signer
  → manually applied by a security engineer after review
```

---

## 13. Workload Identity Federation (WIF)

### The problem with static credentials

Traditional CI/CD stores a GCP service account JSON key as a secret:
```
GitHub Secret: GCP_SA_KEY = { "type": "service_account", "private_key": "-----BEGIN RSA..." }
```

Problems:
- The key is a long-lived credential — if it leaks, it's valid until manually rotated
- Keys are stored in GitHub's secret storage — you're trusting GitHub's security model
- Rotation is manual and often neglected
- You cannot scope a key to "only valid when used by this specific workflow on this branch"

### What WIF does

WIF lets an external identity provider (GitHub, AWS, Azure AD, etc.) exchange **their short-lived tokens**
for **short-lived GCP credentials**, with no static key ever created.

### The exchange flow

```
1. GitHub Actions job starts
   GitHub issues an OIDC token (JWT) to the job:
   {
     "iss": "https://token.actions.githubusercontent.com",
     "sub": "repo:Dajma/gcp-platform:ref:refs/heads/main",
     "aud": "https://iam.googleapis.com/...",
     "exp": <1 hour from now>
   }

2. CI exchanges this JWT with GCP's WIF endpoint:
   POST https://sts.googleapis.com/v1/token
   { subject_token: <github JWT>, audience: <wif pool resource name> }

3. GCP validates:
   - Is the JWT signed by GitHub's OIDC public key? ✓
   - Does the `sub` claim match our allowlist? (repo:Dajma/gcp-platform:ref:refs/heads/main) ✓
   - Has the token expired? ✓

4. GCP returns a short-lived federated token (valid for 1 hour)

5. CI uses the federated token to impersonate the Terraform SA:
   POST https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/terraform-apply@.../generateAccessToken
   { scope: ["https://www.googleapis.com/auth/cloud-platform"] }

6. GCP returns a short-lived SA access token (valid for 1 hour)

7. CI runs terraform apply with this token
   Token expires after 1 hour regardless — no rotation needed
```

### WIF Identity Pool

A **WIF Identity Pool** is the GCP-side configuration that defines:
- Which external IdP is trusted (GitHub, AWS, etc.)
- What claims are valid (which repos, which branches, which environments)
- Which service accounts can be impersonated by federated identities from this pool

We create **separate pools per environment**:
```
wif-pool-nonprod:
  - Provider: GitHub OIDC
  - Allowed sub: repo:Dajma/gcp-platform:ref:refs/heads/main
  - Can impersonate: terraform-apply-nonprod@cicd-platform.iam.gserviceaccount.com

wif-pool-prod:
  - Provider: GitHub OIDC
  - Allowed sub: repo:Dajma/gcp-platform:ref:refs/heads/main
  - Can impersonate: terraform-apply-prod@cicd-platform.iam.gserviceaccount.com
```

Why separate pools? A compromised nonprod pipeline with the nonprod WIF pool token
**cannot** impersonate the prod SA — the prod SA only trusts the prod pool,
and the prod pool only issues credentials to approved workflows.

---

## 14. VPC Service Controls

### The problem

IAM controls **who** can access a resource.
But IAM cannot control **from where** a request originates.

Example: your data scientist has `roles/bigquery.dataViewer` on a sensitive dataset.
IAM allows them to query it. But what if:
- They query it from a coffee shop on an unmanaged laptop?
- Their laptop is compromised and malware exfiltrates the data?
- A compromised service account outside your org calls the BigQuery API?

IAM says "yes" in all these cases because the identity has the right permission.

### What VPC Service Controls does

VPC Service Controls creates an **API-level perimeter** around a set of GCP projects.
API calls to services inside the perimeter are only allowed if the caller is also inside the perimeter.

```
Perimeter: prod-perimeter
  Protected services: bigquery.googleapis.com, storage.googleapis.com, secretmanager.googleapis.com
  Member projects: gke-prod, app-payments-prod, security-project, logging-central

Rule:
  API call to BigQuery:
    Caller in perimeter? → ALLOW (IAM still checked separately)
    Caller outside perimeter? → DENY (even if IAM allows it)
```

"Inside the perimeter" means:
- Traffic originates from a VM in a member project's VPC
- The caller's identity is in the perimeter's access policy
- The caller is connecting from an approved network (VPC, on-prem via VPN)

### What it prevents

- **Data exfiltration via confused deputy**: malware on a VM steals a service account token,
  then calls the BigQuery API from outside GCP → blocked (caller not in perimeter)
- **Accidental public exposure**: a bucket's IAM is misconfigured to `allUsers`,
  but VPC SC blocks any request from the public internet → data still protected
- **Credential theft + replay**: attacker steals OAuth token and replays it from their laptop
  → blocked (their IP/network is not in the perimeter)

### Access levels and exceptions

You can define fine-grained exceptions (called **access levels**):
```
Access level: trusted-corp-network
  Condition: request comes from IP range 203.0.113.0/24 (corporate office)

Access level: trusted-admin-device
  Condition: device is corp-managed (via Endpoint Verification)

Exception: allow-cicd-pipeline
  Condition: request from cicd-platform service account + in approved VPC
```

These exceptions let CI/CD pipelines and on-call engineers access protected resources
from approved contexts while blocking everything else.

### Cost
VPC SC is part of Access Context Manager. The perimeter itself is free.
Access levels and monitoring may have costs at scale. Minimal in this lab.

---

## 15. Shielded VMs — Secure Boot and vTPM

### The problem: firmware and boot-level attacks

Traditional VMs are vulnerable to attacks that occur before the OS even loads:
- **Bootkit**: malicious code injected into the bootloader — persists across OS reinstalls
- **Rootkit**: code that hides itself in the kernel, invisible to the OS
- **Firmware tampering**: attacker modifies VM firmware (UEFI) to persist across reboots
- **VM identity spoofing**: an attacker creates a VM claiming to be a trusted workload

These attacks are essentially invisible to OS-level security tools (antivirus, EDR) because
they operate below the OS.

### What Shielded VMs provide

Shielded VM is a set of three security features that together guarantee the integrity of the
boot chain from firmware → bootloader → OS kernel.

**1. Secure Boot**

Secure Boot enforces that every piece of code in the boot chain is signed by a trusted key.

```
Power on
  ↓
UEFI firmware  (signed by Google)
  ↓
SHIM (signed by Microsoft/Google)
  ↓
GRUB bootloader  (signed)
  ↓
Linux kernel  (signed)
  ↓
OS starts

If any step's signature is invalid → VM refuses to boot
```

This prevents bootkits and tampered bootloaders. An attacker cannot inject code into the
boot chain without an approved signing key.

**2. Virtual Trusted Platform Module (vTPM)**

A TPM is a hardware security chip that:
- Stores cryptographic keys that cannot be extracted from the chip
- Measures (hashes) the boot sequence and records it in Platform Configuration Registers (PCRs)
- Can attest: "this VM booted with this exact sequence of signed components"

In Shielded VMs, the vTPM is a virtualised TPM emulated by Google's hypervisor.

What it enables:
- **Boot attestation**: the VM can cryptographically prove its boot chain was unmodified
- **Sealed secrets**: keys/secrets can be sealed to a specific boot state — if the boot chain changes
  (e.g. a rootkit is installed), the vTPM refuses to unseal the secrets
- **Integration with Confidential Computing**: vTPM is a prerequisite for attestation-based workload identity

**3. Integrity Monitoring**

Shielded VMs capture a **baseline measurement** of the VM's boot sequence when it first boots.
On every subsequent boot, the measurements are compared against the baseline.

If the measurements change (someone modified the bootloader, kernel, or firmware), GCP:
- Flags a violation in Cloud Monitoring
- Sends an alert to Security Command Center
- Logs the deviation in Cloud Audit Logs

This gives you visibility into any boot-level tampering even if the attacker successfully boots the VM.

### Why this matters operationally

- **Compliance**: CIS GCP Benchmark v2.0 requires Shielded VMs on all instances
- **Zero-trust posture**: a VM that can attest its boot state can participate in zero-trust
  network access policies (only allow network access if the VM's vTPM attests a clean boot)
- **Defense in depth**: even if an attacker exploits a kernel vulnerability and installs a rootkit,
  the next reboot will be detected by integrity monitoring
- **Cost**: Shielded VMs have no additional cost on GCP. There is zero reason not to use them.

**Org policy enforcement:**
`compute.requireShieldedVm = true` (Phase 1) — all VMs in all projects must use Shielded VM.
Any attempt to create an unshielded VM is blocked before it starts.

---

## 16. Clarifications and Follow-up Questions

---

### 16.1 What does "bind the group once at the folder level" actually mean?

IAM policies in GCP are attached to a resource — an organisation, a folder, or a project.
When you attach a policy to a folder, every project inside that folder **inherits** it automatically.
You do not have to touch each project individually.

**Concrete example:**

```
Organisation
└── Folder: prod/
    ├── Project: gke-prod
    ├── Project: app-payments-prod
    └── Project: app-orders-prod
```

You run this single command once:

```bash
gcloud resource-manager folders add-iam-policy-binding FOLDER_ID \
  --member="group:platform-admins@example.com" \
  --role="roles/compute.admin"
```

Result:
- `platform-admins` group has `roles/compute.admin` on `gke-prod` — inherited
- `platform-admins` group has `roles/compute.admin` on `app-payments-prod` — inherited
- `platform-admins` group has `roles/compute.admin` on `app-orders-prod` — inherited

Add a fourth project tomorrow under `prod/` — it inherits the binding automatically.
Remove a person from the Google Group — access revoked across all three projects instantly.

**Without folder-level bindings** you would need to run that command three times (once per project),
and repeat it for every new project added. With 50 projects across 10 teams, that is 500 IAM
operations. Miss one and you have a privilege gap or a ghost permission sitting on a decommissioned project.

**The inheritance chain:**

```
Organisation IAM
    ↓ inherited by
Folder IAM  (e.g. prod/)
    ↓ inherited by
Project IAM
    ↓ inherited by
Resource IAM  (e.g. a specific GCS bucket)
```

Bindings flow **downward only** — a folder cannot inherit from a project, a project
cannot inherit from a sibling project. Deny policies (a newer feature) can be used to
override inherited allows, but regular allow policies are additive: a lower-level policy
adds permissions on top of inherited ones, never removes them.

**This is why group membership matters so much.**
The group is the indirection layer between the IAM binding (which rarely changes) and the
people in it (who join and leave constantly). The IAM binding at the folder level points
to the group. Managing access = managing group membership in Cloud Identity/Workspace.
You never touch IAM policies to onboard or offboard a person.

---

### 16.2 If GCP VPCs are global and regions communicate freely, what is the purpose of subnets?

Good challenge. The global VPC and free inter-region communication answers "can A talk to B?"
Subnets answer four different questions: **what IP does a resource get, where does it live,
what policies apply to it, and what services can attach to it?**

**1. IP address assignment**
Resources (VMs, GKE nodes, Cloud SQL) get IPs from subnets, not from the VPC directly.
A VM in `us-central1` gets an IP from `subnet-gke-nodes-prod` (10.0.0.0/20).
A VM in `europe-west1` gets an IP from `subnet-gke-nodes-prod-eu` (10.16.0.0/20).
Without subnets, GCP has no mechanism to assign IPs to resources — the VPC itself has
no IP range, only subnets do.

**2. Regional placement**
A subnet is tied to a region. When you create a VM in `us-central1`, it must be placed
in a subnet that exists in `us-central1`. The subnet enforces where the resource physically runs.
This is critical for latency, data residency compliance, and disaster recovery zone planning.

**3. Policy attachment point**
Several GCP features attach at the subnet level:
- **Private Google Access** — enable per subnet. VMs in that subnet can reach Google APIs privately.
  A different subnet in the same VPC can have PGA disabled.
- **Secondary IP ranges** — GKE pod and service CIDRs are defined as secondary ranges on a subnet.
  This is how VPC-native GKE clusters allocate pod IPs without consuming primary subnet space.
- **VPC Flow Logs** — enabled per subnet. You pay for what you log; enabling it only on
  sensitive subnets saves cost while maintaining visibility where it matters.
- **Cloud NAT** — configured per region and per subnet. You can NAT only specific subnets
  through a NAT gateway, giving different egress behaviour to different workload tiers.

**4. Network segmentation and access control**
Firewall rules in GCP target VMs (via network tags or service accounts), not subnets directly.
However, subnets define the IP ranges, and firewall rules can use IP ranges as source/destination.
Example: allow traffic from `10.0.0.0/20` (the GKE nodes subnet) to `10.0.16.0/24` (the SQL subnet)
on port 5432. Without subnets with defined CIDRs, you cannot write targeted firewall rules.

**Summary:**
The global VPC gives you a single routing domain with no cross-region friction.
Subnets give you IP allocation, regional placement, per-subnet feature control, and the
CIDR ranges needed for meaningful firewall rules. They solve different problems.

---

### 16.3 In Shared VPC, does IAM from the host project apply to the spoke projects?

**No. IAM does not cross project boundaries in either direction.**

The Shared VPC host project and the service (spoke) projects have completely separate IAM policies.
What the host project controls is **network resource access** only — not project-level IAM.

Here is the precise boundary:

| What the host project controls | What it does NOT control |
|---|---|
| Who can use which subnets in its VPC | IAM inside the service project |
| Who can create/modify firewall rules | Who can deploy VMs or GKE clusters in the service project |
| Who can manage Cloud NAT and DNS | Who can access GCS buckets in the service project |
| Network admin roles on the VPC | Any non-networking resource in the service project |

**The specific permission that governs Shared VPC subnet access:**

The host project's network admin grants `roles/compute.networkUser` on a specific subnet
to the service account (or group) that will deploy resources into that subnet:

```bash
# Grant gke-prod's GKE SA permission to use subnet-gke-nodes-prod in the host project
gcloud compute networks subnets add-iam-policy-binding subnet-gke-nodes-prod \
  --region=us-central1 \
  --member="serviceAccount:gke-sa@gke-prod.iam.gserviceaccount.com" \
  --role="roles/compute.networkUser" \
  --project=networking-host-prod
```

This gives `gke-sa` permission to attach VMs to that subnet.
It gives it **nothing else** — no access to other subnets, no access to the host project's
other resources, no access to other service projects.

**The separation is exactly what we want:**
- Network engineers manage the host project — subnets, NAT, DNS, firewalls
- Application teams manage their own service projects — deployments, IAM, application config
- Neither has visibility or control over the other's domain

---

### 16.4 Is it true that one VPC = one project, access-wise?

**By default, yes. With Shared VPC, no.**

**Default behaviour (no Shared VPC):**
A VPC is created in a project. Only resources in that project can attach to subnets in that VPC.
There is no mechanism for a VM in Project B to get an IP from Project A's subnet — unless
you use VPC Peering (which connects VPCs, not subnets) or Shared VPC.

**With Shared VPC:**
The host project's VPC can be used by multiple service projects. The VPC is still owned by
one project (the host), but multiple projects place resources into its subnets.
So the accurate statement is: **one VPC = one owning project, but potentially many consuming projects.**

**With VPC Peering:**
Two separate VPCs (in separate projects) exchange routes. They remain separate VPCs —
resources in each project keep their own VPC's IPs and routing. It is connectivity between
VPCs, not sharing a single VPC. Resources in Project A do not get IPs from Project B's subnets.

**The practical consequence for this design:**

```
networking-host-prod (owns prod-vpc)
  └── subnet-gke-nodes-prod  10.0.0.0/20
      ├── gke-prod nodes: 10.0.0.1 – 10.0.0.100   ← resources in gke-prod project
      ├── app-payments VM: 10.0.0.101              ← resources in app-payments-prod project
      └── security-project VM: 10.0.0.102          ← resources in security-project
```

Multiple projects, one subnet, one VPC, one project owning it — this is exactly Shared VPC.

---

### 16.5 Is the firewall at the VPC level or subnet level?

**Neither — GCP firewalls are applied at the VM (instance) level.**

This is one of the most important differences from traditional networking (and from AWS,
where Security Groups are attached to ENIs and NACLs to subnets).

**How GCP firewall rules actually work:**

A firewall rule is attached to a VPC and targets VMs via **network tags** or **service accounts**:

```hcl
# Allow port 5432 from GKE nodes to Cloud SQL VMs
resource "google_compute_firewall" "allow_gke_to_sql" {
  name    = "allow-gke-to-sql"
  network = "prod-vpc"

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  # Source: any VM tagged "gke-node"
  source_tags = ["gke-node"]

  # Target: any VM tagged "cloud-sql-proxy"
  target_tags = ["cloud-sql-proxy"]
}
```

When a packet arrives at a VM, GCP evaluates all firewall rules in the VPC that apply
to that VM (based on its tags or service account). The rule is enforced at the hypervisor
level — the VM never even sees blocked packets.

**There is no NACL equivalent in GCP.** You cannot block traffic at the subnet boundary.
If a VM has a firewall rule allowing port 80, it receives port-80 traffic regardless of
which subnet it is in.

**Hierarchical Firewall Policies (what we use):**

These work differently — they are attached at the organisation or folder level and applied
**before** project-level rules. They define baseline rules that cannot be overridden by
project-level rules:

```
Evaluation order for a packet:
  1. Hierarchical firewall policies (org level)
  2. Hierarchical firewall policies (folder level)
  3. Project-level VPC firewall rules
  4. Implicit deny-all (if no rule matched)
```

Our design:
- **Org-level policy**: deny all ingress by default; allow IAP (Identity-Aware Proxy) for SSH
- **Project-level rules**: workload-specific allows (GKE pod-to-pod, LB health checks, etc.)

This means: even if an application team adds a misconfigured firewall rule in their project,
the org-level deny policy is evaluated first and blocks unexpected traffic from the internet.

---

### 16.6 Team Ownership Model — Who Owns What?

Your understanding is correct. The project/folder structure maps directly to team ownership:

| Infrastructure | Owner | What they control |
|---|---|---|
| `infrastructure/` folder | **Network engineers** | VPCs, subnets, Cloud NAT, Cloud DNS, firewall baselines, VPN/Interconnect |
| `security/` folder | **Security team** | KMS keyrings, Secret Manager, SCC policies, log sinks, Binary Auth policies, VPC Service Controls |
| `shared-services/` folder | **Platform / DevOps team** | Artifact Registry, CI/CD pipelines, WIF providers, shared tooling |
| `prod/` folder | **Platform team** (deploy) + **App teams** (own their project) | GKE clusters, app projects — platform deploys the infrastructure, app teams own what runs on it |
| `nonprod/` folder | **App teams** (more autonomy) | Dev/staging clusters, application deployments |
| `sandbox/` folder | **Anyone** | No guardrails, self-service, auto-cleanup |
| Org-level policies + audit logging | **Platform / Security lead** | Controls that apply everywhere |

**This is how Stripe, Shopify, and similar companies operate:**

- Network engineers own the network and nothing else. They have no access to application code or secrets.
- Security engineers own the key material and audit trail. They can see logs but cannot deploy workloads.
- Application teams own their projects. They cannot touch networking — they get allocated a subnet and work within it.
- The platform team operates the glue: CI/CD, the Terraform modules, GKE clusters. They have broad access but are bound by the same Terraform-first, PR-reviewed change process as everyone else.

**The IAM model enforces this separation:**

```
group: network-engineers@
  → roles/compute.networkAdmin  on infrastructure/ folder
  → roles/compute.xpnAdmin      on org (to manage Shared VPC attachments)
  → NO access to security/, prod/, nonprod/ folders

group: secops@
  → roles/cloudkms.admin        on security/ folder
  → roles/securitycenter.admin  on org
  → roles/logging.admin         on logging-central project
  → NO access to infrastructure/, prod/ folders

group: platform-admins@
  → roles/container.admin       on prod/, nonprod/ folders
  → roles/viewer                on infrastructure/ folder (read-only visibility)
  → NO access to security/ folder (cannot touch KMS keys)

group: developers@
  → roles/viewer                on nonprod/ folder only
  → NO access to prod/, infrastructure/, security/ folders
```

Each group can only do what their role requires. A network engineer cannot accidentally
(or intentionally) read a Secret Manager secret. A developer cannot modify a firewall rule.
A security engineer cannot deploy a workload to production. This is separation of duties
implemented through IAM — not just policy, but technically enforced.
