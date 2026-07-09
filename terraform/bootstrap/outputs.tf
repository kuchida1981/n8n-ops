output "state_bucket" {
  description = "GCS bucket name to use as the terraform/main remote state backend."
  value       = google_storage_bucket.tfstate.name
}

output "workload_identity_provider" {
  description = "Full resource name to set as GCP_WORKLOAD_IDENTITY_PROVIDER in GitHub Actions secrets."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "terraform_ci_service_account_email" {
  description = "Service account email to set as GCP_SERVICE_ACCOUNT_EMAIL in GitHub Actions secrets."
  value       = google_service_account.terraform_ci.email
}
