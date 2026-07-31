resource "google_project_service" "required" {
  for_each = toset([
    "compute.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
    "iap.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Remote state bucket used by terraform/main.
resource "google_storage_bucket" "tfstate" {
  name                        = "${var.project_id}-n8n-tfstate"
  project                     = var.project_id
  location                    = upper(var.region)
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  depends_on = [google_project_service.required]
}

# Workload Identity Federation: lets GitHub Actions authenticate to GCP
# without a long-lived service account key.
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github-actions-pool-n8n"
  display_name              = "GitHub Actions (n8n-ops)"

  depends_on = [google_project_service.required]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-provider"
  display_name                       = "GitHub Actions Provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  # Only this exact repository may mint tokens through this provider.
  attribute_condition = "assertion.repository == \"${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Service account impersonated by GitHub Actions to run terraform/main.
resource "google_service_account" "terraform_ci" {
  project      = var.project_id
  account_id   = "terraform-ci-n8n"
  display_name = "Terraform CI for n8n-ops (GitHub Actions)"
}

resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.terraform_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

resource "google_storage_bucket_iam_member" "terraform_ci_state_access" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform_ci.email}"
}

# roles/storage.objectAdmin above is object-level only and does not include
# storage.buckets.get - discovered when `terraform plan` for bootstrap
# itself failed trying to refresh google_storage_bucket.tfstate (see Issue
# #41). legacyBucketReader adds bucket-metadata read without granting any
# write access.
resource "google_storage_bucket_iam_member" "terraform_ci_state_bucket_reader" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.terraform_ci.email}"
}

# Broad-but-scoped project roles the CI service account needs to manage
# the VM, disks, firewall, Secret Manager entries and the VM runtime SA.
#
# iap.tunnelResourceAccessor + compute.osAdminLogin: lets the n8n-deploy.yml
# workflow reach the VM via `gcloud compute ssh --tunnel-through-iap` to run
# `docker compose pull && up -d` after a version bump, without touching the
# Tailscale ACL (which is already jointly owned by vaultwarden-ops' state -
# see Issue #12). OS Login mints short-lived SSH keys tied to this SA's own
# IAM identity, so there's no persistent key to manage or rotate.
# osAdminLogin (not the plain osLogin) is required specifically because
# /opt/n8n/app, /opt/n8n/.env (mode 600) and the docker socket are all
# root-owned - the deploy command needs sudo, which only osAdminLogin grants
# via OS Login's sudoers group.
resource "google_project_iam_member" "terraform_ci_roles" {
  for_each = toset([
    "roles/compute.admin",
    "roles/secretmanager.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/iap.tunnelResourceAccessor",
    "roles/compute.osAdminLogin",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform_ci.email}"
}

# Read-only roles so CI can run `terraform plan` (refresh) against
# terraform/bootstrap itself - see Issue #41. CI is intentionally never
# granted write/admin access here: bootstrap creates this very service
# account, the WIF pool it authenticates through, and its own project IAM
# bindings, so an apply-capable CI identity could grant itself broader
# permissions unsupervised. Plan-only needs read access to those same
# resource types:
#   - serviceUsageViewer: refresh google_project_service.required
#   - iam.workloadIdentityPoolViewer: refresh the WIF pool/provider
#   - iam.securityReviewer: refresh IAM policy bindings (project, service
#     account, and bucket level) without granting the ability to change them
resource "google_project_iam_member" "terraform_ci_readonly_roles" {
  for_each = toset([
    "roles/serviceusage.serviceUsageViewer",
    "roles/iam.workloadIdentityPoolViewer",
    "roles/iam.securityReviewer",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform_ci.email}"
}

# Lets the Ops Agent installed on the n8n VM (see terraform/main's
# startup-script.sh.tftpl) report memory/disk/process metrics and logs to
# Cloud Monitoring/Logging. Granted here rather than in terraform/main
# alongside the rest of that SA's roles (iam.tf) because this is a
# project-level IAM policy change, and terraform-ci is deliberately never
# given resourcemanager.projects.setIamPolicy - see terraform_ci_roles'
# comment above for why an apply-capable CI identity must not be able to
# grant IAM roles itself. The member string is built from the account_id
# literal ("n8n-vm") rather than a resource reference, since that service
# account is a resource in terraform/main's own state, a separate root
# module this one has no data source into.
resource "google_project_iam_member" "n8n_vm_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:n8n-vm@${var.project_id}.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "n8n_vm_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:n8n-vm@${var.project_id}.iam.gserviceaccount.com"
}
