variable "project_id" {
  description = "GCP project ID that will host the n8n infrastructure."
  type        = string
}

variable "region" {
  description = "Default region for regional resources (state bucket). Must be one of GCP's Compute Engine Always Free e2-micro regions (us-west1/us-central1/us-east1) to keep the VM itself free."
  type        = string
  default     = "us-west1"
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the Terraform CI service account, in \"owner/repo\" form."
  type        = string
}
