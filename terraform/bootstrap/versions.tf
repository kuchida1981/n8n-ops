terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.39"
    }
  }

  # Intentionally local state: this config creates the very resources
  # (GCS bucket, Workload Identity Federation) that terraform/main needs
  # before it can use a remote backend or keyless CI auth. Run this once,
  # by hand, from your own machine.
}

provider "google" {
  project = var.project_id
  region  = var.region
}
