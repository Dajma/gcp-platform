#!/usr/bin/env bash
# Creates the Terraform state GCS bucket — run this once, manually, before any Terraform.
# This script is idempotent: re-running it will detect the existing bucket and skip creation.

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
# Fill these in before running. Do NOT commit filled-in values if they contain
# sensitive IDs — use environment variables instead.

ORG_PREFIX="${ORG_PREFIX:-}"         # e.g. "myorg" — used in bucket name
ADMIN_PROJECT_ID="${ADMIN_PROJECT_ID:-}"  # Project that will own the bucket
REGION="${REGION:-us-central1}"
TF_SA_EMAIL="${TF_SA_EMAIL:-}"       # terraform-org-admin@PROJECT.iam.gserviceaccount.com

# ── Input validation ─────────────────────────────────────────────────────────
if [[ -z "${ORG_PREFIX}" || -z "${ADMIN_PROJECT_ID}" || -z "${TF_SA_EMAIL}" ]]; then
  echo "ERROR: Required environment variables not set."
  echo ""
  echo "  export ORG_PREFIX='myorg'"
  echo "  export ADMIN_PROJECT_ID='my-admin-project-123'"
  echo "  export TF_SA_EMAIL='terraform-org-admin@my-admin-project-123.iam.gserviceaccount.com'"
  echo "  export REGION='us-central1'  # optional, defaults to us-central1"
  echo ""
  exit 1
fi

# ── Derive bucket name (deterministic from project ID to be idempotent) ──────
# Using first 8 chars of project ID hash ensures the name is stable on re-runs
HASH=$(echo -n "${ADMIN_PROJECT_ID}" | sha256sum | cut -c1-8)
BUCKET_NAME="${ORG_PREFIX}-terraform-state-${HASH}"
BUCKET_URI="gs://${BUCKET_NAME}"

echo "=========================================="
echo "  Terraform Backend Bootstrap"
echo "=========================================="
echo "  Admin project : ${ADMIN_PROJECT_ID}"
echo "  Region        : ${REGION}"
echo "  Bucket name   : ${BUCKET_NAME}"
echo "  Terraform SA  : ${TF_SA_EMAIL}"
echo "=========================================="
echo ""

# ── Check if bucket already exists ───────────────────────────────────────────
if gcloud storage buckets describe "${BUCKET_URI}" --project="${ADMIN_PROJECT_ID}" &>/dev/null; then
  echo "✓ Bucket ${BUCKET_NAME} already exists — skipping creation."
else
  echo "→ Creating GCS bucket..."
  gcloud storage buckets create "${BUCKET_URI}" \
    --project="${ADMIN_PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention

  echo "✓ Bucket created."
fi

# ── Enable versioning ─────────────────────────────────────────────────────────
echo "→ Enabling object versioning..."
gcloud storage buckets update "${BUCKET_URI}" --versioning
echo "✓ Versioning enabled."

# ── Set soft-delete policy (7 days) ──────────────────────────────────────────
echo "→ Setting soft-delete retention to 7 days..."
gcloud storage buckets update "${BUCKET_URI}" --soft-delete-duration=7d
echo "✓ Soft-delete policy set."

# ── Grant Terraform SA object-level access (not bucket admin) ────────────────
echo "→ Granting storage.objectAdmin to Terraform SA..."
gcloud storage buckets add-iam-policy-binding "${BUCKET_URI}" \
  --member="serviceAccount:${TF_SA_EMAIL}" \
  --role="roles/storage.objectAdmin"
echo "✓ IAM binding applied."

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "  Bootstrap Complete"
echo "=========================================="
echo ""
echo "  Bucket name: ${BUCKET_NAME}"
echo ""
echo "  Next steps:"
echo "  1. Record the bucket name above."
echo "  2. Copy terraform/environments/dev/backend.tfvars.template"
echo "       → terraform/environments/dev/backend.tfvars"
echo "     and fill in:"
echo "       bucket = \"${BUCKET_NAME}\""
echo "  3. Repeat for staging and prod environments."
echo "  4. Do NOT commit backend.tfvars files — they are gitignored."
echo "     Use environment variables or a secrets manager in CI."
echo ""
