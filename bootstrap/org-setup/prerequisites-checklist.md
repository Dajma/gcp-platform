# Phase 0 — Prerequisites Checklist

Run these steps in order. Check each box only after verifying the step succeeded.

All commands assume you are authenticated as a Cloud Identity / Workspace Super Admin
(`gcloud auth login` with your admin account).

---

## Step 1 — Collect GCP Facts

```bash
# Get your organization ID
gcloud organizations list
# Output: DISPLAY_NAME  ID           DIRECTORY_CUSTOMER_ID
# Record the numeric ID (e.g. 123456789012)
export ORG_ID="123456789012"

# Get your billing account ID
gcloud billing accounts list
# Output: ACCOUNT_ID            NAME           OPEN  MASTER_ACCOUNT_ID
# Record the ACCOUNT_ID (format: XXXXXX-XXXXXX-XXXXXX)
export BILLING_ACCOUNT_ID="XXXXXX-XXXXXX-XXXXXX"

# Choose your primary region
export PRIMARY_REGION="us-central1"

# Choose your org name prefix (used in resource naming, lowercase, no spaces)
export ORG_PREFIX="myorg"
```

- [ ] `ORG_ID` recorded
- [ ] `BILLING_ACCOUNT_ID` recorded
- [ ] `PRIMARY_REGION` chosen
- [ ] `ORG_PREFIX` chosen (lowercase slug, e.g. `myorg`)

---

## Step 2 — Create the Admin Project

This project hosts the Terraform SA and the state bucket. It is NOT a workload project.

```bash
export ADMIN_PROJECT_ID="${ORG_PREFIX}-terraform-admin"

# Create the project under your org
gcloud projects create "${ADMIN_PROJECT_ID}" \
  --organization="${ORG_ID}" \
  --name="Terraform Admin"

# Link billing (required to create resources in the project)
gcloud billing projects link "${ADMIN_PROJECT_ID}" \
  --billing-account="${BILLING_ACCOUNT_ID}"

# Set as default for subsequent gcloud commands
gcloud config set project "${ADMIN_PROJECT_ID}"
```

- [ ] Admin project created: `${ORG_PREFIX}-terraform-admin`
- [ ] Billing linked to admin project

---

## Step 3 — Enable Required APIs

These APIs must be enabled on the admin project before Terraform can call them.

```bash
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  storage.googleapis.com \
  cloudbilling.googleapis.com \
  serviceusage.googleapis.com \
  cloudidentity.googleapis.com \
  --project="${ADMIN_PROJECT_ID}"
```

- [ ] APIs enabled on admin project

---

## Step 4 — Create the Terraform Super-Admin Service Account

```bash
export TF_SA_NAME="terraform-org-admin"
export TF_SA_EMAIL="${TF_SA_NAME}@${ADMIN_PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts create "${TF_SA_NAME}" \
  --display-name="Terraform Org Admin" \
  --description="Super-admin SA for platform Terraform — impersonation only, no exported keys" \
  --project="${ADMIN_PROJECT_ID}"

echo "SA created: ${TF_SA_EMAIL}"
```

- [ ] Service account `terraform-org-admin` created in admin project
- [ ] **No JSON key exported** (intentional — do not create one)

---

## Step 5 — Grant Org-Level Roles to the Terraform SA

See `required-roles.md` for rationale on each role.

```bash
# Array of roles to grant at org level
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
  echo "Granting ${ROLE}..."
  gcloud organizations add-iam-policy-binding "${ORG_ID}" \
    --member="serviceAccount:${TF_SA_EMAIL}" \
    --role="${ROLE}"
done

echo "All org-level roles granted."
```

- [ ] All org-level roles granted to Terraform SA
- [ ] Verified with: `gcloud organizations get-iam-policy ${ORG_ID} --flatten="bindings[].members" --filter="bindings.members:serviceAccount:${TF_SA_EMAIL}"`

---

## Step 6 — Grant SA the Ability to Be Impersonated

This allows your personal account (and later the CI WIF SA) to impersonate the Terraform SA
without needing to export a key.

```bash
# Replace with your personal Google account
YOUR_PERSONAL_EMAIL="your-email@example.com"

gcloud iam service-accounts add-iam-policy-binding "${TF_SA_EMAIL}" \
  --project="${ADMIN_PROJECT_ID}" \
  --member="user:${YOUR_PERSONAL_EMAIL}" \
  --role="roles/iam.serviceAccountTokenCreator"
```

- [ ] `roles/iam.serviceAccountTokenCreator` granted to your personal account on the SA

---

## Step 7 — Create the Terraform State Bucket

```bash
cd bootstrap/terraform-backend/

export ORG_PREFIX="${ORG_PREFIX}"
export ADMIN_PROJECT_ID="${ADMIN_PROJECT_ID}"
export REGION="${PRIMARY_REGION}"
export TF_SA_EMAIL="${TF_SA_EMAIL}"

./create-backend.sh
```

Record the bucket name output by the script.

- [ ] State bucket created
- [ ] Bucket name recorded: `_________________________`

---

## Step 8 — Populate Backend Configs

```bash
BUCKET_NAME="<bucket name from step 7>"

# Copy templates and fill in the bucket name
for ENV in dev staging prod; do
  cp "terraform/environments/${ENV}/backend.tfvars.template" \
     "terraform/environments/${ENV}/backend.tfvars"
  sed -i "s/BUCKET_NAME_PLACEHOLDER/${BUCKET_NAME}/" \
     "terraform/environments/${ENV}/backend.tfvars"
done
```

- [ ] `terraform/environments/dev/backend.tfvars` populated
- [ ] `terraform/environments/staging/backend.tfvars` populated
- [ ] `terraform/environments/prod/backend.tfvars` populated
- [ ] Confirmed `*.tfvars` (non-template) files are in `.gitignore` and NOT staged

---

## Step 9 — Populate Environment Variables

```bash
# Edit each file with real values
# These files ARE committed (they contain no secrets, only variable names and regions)
# Fill in org_id, billing_account_id, primary_region, org_domain
vim terraform/environments/dev/terraform.tfvars
```

- [ ] `terraform/environments/dev/terraform.tfvars` populated with real GCP IDs
- [ ] Verified no secrets are in any `.tfvars` file

---

## Step 10 — Verify Impersonation Works

```bash
# Activate impersonation for your gcloud session
gcloud config set auth/impersonate_service_account "${TF_SA_EMAIL}"

# Test: list projects (should work if roles are correct)
gcloud projects list --organization="${ORG_ID}"

# Test: access the state bucket
gcloud storage ls "gs://${BUCKET_NAME}/"

# When done testing, disable impersonation for your normal session
gcloud config unset auth/impersonate_service_account
```

- [ ] `gcloud projects list` works under impersonation
- [ ] `gcloud storage ls` works on state bucket under impersonation

---

## Step 11 — Install Pre-commit Hooks

```bash
pip install pre-commit detect-secrets
pre-commit install
pre-commit run --all-files  # should pass (no TF files yet, just templates)
```

- [ ] `pre-commit` installed and hooks registered

---

## Phase 0 Complete

All manual prerequisites are in place. Report back and confirm before Phase 1 begins.
