#!/usr/bin/env bash
# Bootstrap orchestration script.
# Guides you through Phase 0 manual steps in sequence with guard checks.
# Re-running is safe — each step checks if its work is already done.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Guard: must be run from repo root ────────────────────────────────────────
if [[ ! -f "CLAUDE.md" ]]; then
  error "Run this script from the repository root (where CLAUDE.md lives)."
fi

# ── Guard: gcloud must be installed and authenticated ────────────────────────
if ! command -v gcloud &>/dev/null; then
  error "gcloud CLI not found. Install from: https://cloud.google.com/sdk/docs/install"
fi

ACTIVE_ACCOUNT=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | head -1)
if [[ -z "${ACTIVE_ACCOUNT}" ]]; then
  error "No active gcloud account. Run: gcloud auth login"
fi
info "Authenticated as: ${ACTIVE_ACCOUNT}"

# ── Load environment variables ───────────────────────────────────────────────
# These can be set in the environment or in a local .env file (gitignored)
if [[ -f ".env.bootstrap" ]]; then
  # shellcheck disable=SC1091
  source ".env.bootstrap"
  info "Loaded .env.bootstrap"
fi

: "${ORG_PREFIX:?Set ORG_PREFIX (e.g. export ORG_PREFIX=myorg)}"
: "${ADMIN_PROJECT_ID:?Set ADMIN_PROJECT_ID}"
: "${ORG_ID:?Set ORG_ID (numeric, from: gcloud organizations list)}"
: "${BILLING_ACCOUNT_ID:?Set BILLING_ACCOUNT_ID (from: gcloud billing accounts list)}"
: "${PRIMARY_REGION:=us-central1}"
: "${YOUR_PERSONAL_EMAIL:?Set YOUR_PERSONAL_EMAIL}"

TF_SA_NAME="terraform-org-admin"
TF_SA_EMAIL="${TF_SA_NAME}@${ADMIN_PROJECT_ID}.iam.gserviceaccount.com"

echo ""
echo "══════════════════════════════════════════"
echo "  GCP Platform Bootstrap — Phase 0"
echo "══════════════════════════════════════════"
echo "  Org ID         : ${ORG_ID}"
echo "  Admin project  : ${ADMIN_PROJECT_ID}"
echo "  Billing account: ${BILLING_ACCOUNT_ID}"
echo "  Region         : ${PRIMARY_REGION}"
echo "  Terraform SA   : ${TF_SA_EMAIL}"
echo "══════════════════════════════════════════"
echo ""
read -rp "Proceed? [y/N] " CONFIRM
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }

# ── Step 1: Create admin project ─────────────────────────────────────────────
echo ""
info "Step 1: Admin project..."
if gcloud projects describe "${ADMIN_PROJECT_ID}" &>/dev/null; then
  success "Admin project ${ADMIN_PROJECT_ID} already exists."
else
  gcloud projects create "${ADMIN_PROJECT_ID}" \
    --organization="${ORG_ID}" \
    --name="Terraform Admin"
  success "Admin project created: ${ADMIN_PROJECT_ID}"
fi

# Link billing
LINKED=$(gcloud billing projects describe "${ADMIN_PROJECT_ID}" --format="value(billingAccountName)" 2>/dev/null || true)
if [[ -n "${LINKED}" ]]; then
  success "Billing already linked to admin project."
else
  gcloud billing projects link "${ADMIN_PROJECT_ID}" --billing-account="${BILLING_ACCOUNT_ID}"
  success "Billing linked to admin project."
fi

# ── Step 2: Enable APIs ───────────────────────────────────────────────────────
echo ""
info "Step 2: Enabling required APIs on admin project..."
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  storage.googleapis.com \
  cloudbilling.googleapis.com \
  serviceusage.googleapis.com \
  cloudidentity.googleapis.com \
  --project="${ADMIN_PROJECT_ID}"
success "APIs enabled."

# ── Step 3: Create Terraform SA ───────────────────────────────────────────────
echo ""
info "Step 3: Terraform service account..."
if gcloud iam service-accounts describe "${TF_SA_EMAIL}" --project="${ADMIN_PROJECT_ID}" &>/dev/null; then
  success "SA ${TF_SA_EMAIL} already exists."
else
  gcloud iam service-accounts create "${TF_SA_NAME}" \
    --display-name="Terraform Org Admin" \
    --description="Super-admin SA for platform Terraform — impersonation only, no exported keys" \
    --project="${ADMIN_PROJECT_ID}"
  success "SA created: ${TF_SA_EMAIL}"
fi

# ── Step 4: Grant org-level roles ─────────────────────────────────────────────
echo ""
info "Step 4: Granting org-level roles to Terraform SA..."
ROLES=(
  "roles/resourcemanager.organizationAdmin"
  "roles/resourcemanager.folderAdmin"
  "roles/resourcemanager.projectCreator"
  "roles/resourcemanager.projectDeleter"
  "roles/billing.admin"
  "roles/iam.organizationRoleAdmin"
  "roles/iam.securityAdmin"
  "roles/orgpolicy.policyAdmin"
  "roles/logging.admin"
  "roles/compute.xpnAdmin"
  "roles/serviceusage.serviceUsageAdmin"
  "roles/accesscontextmanager.policyAdmin"
)

for ROLE in "${ROLES[@]}"; do
  gcloud organizations add-iam-policy-binding "${ORG_ID}" \
    --member="serviceAccount:${TF_SA_EMAIL}" \
    --role="${ROLE}" \
    --condition=None \
    --quiet
  success "  ${ROLE}"
done

# ── Step 5: Grant impersonation to personal account ───────────────────────────
echo ""
info "Step 5: Granting impersonation rights to ${YOUR_PERSONAL_EMAIL}..."
gcloud iam service-accounts add-iam-policy-binding "${TF_SA_EMAIL}" \
  --project="${ADMIN_PROJECT_ID}" \
  --member="user:${YOUR_PERSONAL_EMAIL}" \
  --role="roles/iam.serviceAccountTokenCreator"
success "Impersonation granted."

# ── Step 6: Create state bucket ───────────────────────────────────────────────
echo ""
info "Step 6: Creating Terraform state bucket..."
export ORG_PREFIX ADMIN_PROJECT_ID REGION="${PRIMARY_REGION}" TF_SA_EMAIL
./bootstrap/terraform-backend/create-backend.sh

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo "  Phase 0 Bootstrap Complete"
echo "══════════════════════════════════════════"
echo ""
echo "  Manual steps still required:"
echo "  1. Populate terraform/environments/*/backend.tfvars"
echo "     (copy from *.template and fill in bucket name)"
echo "  2. Populate terraform/environments/dev/terraform.tfvars"
echo "     with real org_id, billing_account_id, primary_region, org_domain"
echo "  3. Install pre-commit: pip install pre-commit && pre-commit install"
echo "  4. Verify impersonation:"
echo "     gcloud config set auth/impersonate_service_account ${TF_SA_EMAIL}"
echo "     gcloud projects list --organization=${ORG_ID}"
echo "     gcloud config unset auth/impersonate_service_account"
echo ""
echo "  Then report back to confirm Phase 0 complete before Phase 1 begins."
echo ""
