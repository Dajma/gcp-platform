# Terraform Backend — Manual Bootstrap

## Why This Is Manual

Terraform cannot manage the GCS bucket that stores its own state. This is the classic "chicken-and-egg" problem: if you put the state bucket in Terraform, where does Terraform's own state live? Storing the bootstrap bucket state locally is also not an option for team environments.

**Solution:** Create the state bucket manually once, then never touch it with `terraform destroy`. All subsequent Terraform layers use this bucket as their remote backend.

See `ADR-003-bootstrap-approach.md` for the full decision rationale.

## Prerequisites

- `gcloud` CLI installed and authenticated
- `roles/storage.admin` or `roles/owner` on the project where the bucket will live (your personal admin project, not a platform project)
- Billing enabled on the admin project

## What to Create

| Property | Value |
|---|---|
| Bucket name | `{ORG_PREFIX}-terraform-state-{RANDOM_SUFFIX}` (globally unique) |
| Location | Your chosen primary region (e.g. `us-central1`) |
| Storage class | `STANDARD` |
| Uniform bucket-level access | **ENABLED** (no per-object ACLs) |
| Versioning | **ENABLED** (allows rollback of corrupted state) |
| Soft delete policy | 7 days minimum |
| Public access prevention | **ENFORCED** |
| Retention policy | None (Terraform manages state rewrites) |

## How to Create

Use the provided script or run manually:

```bash
# Option A: Use the provided script
chmod +x bootstrap/terraform-backend/create-backend.sh
./bootstrap/terraform-backend/create-backend.sh

# Option B: Manual gcloud commands
ORG_PREFIX="myorg"   # Replace with your org name slug
REGION="us-central1" # Replace with your chosen region
PROJECT_ID="your-admin-project-id"

BUCKET_NAME="${ORG_PREFIX}-terraform-state-$(openssl rand -hex 4)"
echo "Creating bucket: ${BUCKET_NAME}"

gcloud storage buckets create "gs://${BUCKET_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --uniform-bucket-level-access \
  --public-access-prevention

gcloud storage buckets update "gs://${BUCKET_NAME}" \
  --versioning

gcloud storage buckets update "gs://${BUCKET_NAME}" \
  --soft-delete-duration=7d

echo "Bucket created: ${BUCKET_NAME}"
echo "Record this name — you will need it in all backend configs."
```

## After Creating the Bucket

1. Record the bucket name — you will use it in every `backend.tfvars` file
2. Update `terraform/environments/dev/backend.tfvars.template` → `backend.tfvars` with the real bucket name
3. Do the same for `staging` and `prod` templates
4. **Never run `terraform destroy` against the admin project that contains this bucket**
5. The bucket will later be imported into Terraform management (with `prevent_destroy = true`) in Phase 5

## State File Layout

Each Terraform layer uses a distinct prefix (key) within the same bucket:

```
gs://{bucket-name}/
├── platform/folders/terraform.tfstate
├── platform/org-policies/terraform.tfstate
├── platform/audit-logging/terraform.tfstate
├── networking/hub-prod/terraform.tfstate
├── networking/hub-nonprod/terraform.tfstate
├── security/kms/terraform.tfstate
├── projects/logging-central/terraform.tfstate
├── projects/security/terraform.tfstate
└── ...
```

Separate state files mean:
- A broken `terraform destroy` on networking cannot wipe platform resources
- Teams can work on different layers in parallel without state lock contention
- Blast radius of a Terraform mistake is bounded to one layer

## Security Controls on the Bucket

After creation, apply these IAM bindings (principle of least privilege):

```bash
# Only the Terraform SA should have write access
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member="serviceAccount:terraform-org-admin@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"

# Optionally, your personal account for emergency access (break-glass)
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member="user:your-email@example.com" \
  --role="roles/storage.objectViewer"
```

Do NOT grant `roles/storage.admin` to the Terraform SA — it doesn't need bucket-level admin, only object-level access.

## Cost

`# [FREE]` — State files are typically < 1MB per layer. GCS free tier covers 5GB; you will not come close to that threshold.
