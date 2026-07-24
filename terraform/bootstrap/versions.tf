terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.39"
    }
  }

  # This config creates the very resources (GCS bucket, Workload Identity
  # Federation) that terraform/main needs before it can use a remote backend
  # or keyless CI auth, and that this backend block itself depends on. So a
  # truly first-ever run in a brand new GCP project still needs one manual,
  # by-hand local-state apply before this block can be enabled - see
  # README.md's bootstrap setup section for that one-time sequence. Once the
  # bucket exists, state lives here (not on any one machine) so any operator
  # can pick up bootstrap changes without losing track of state.
  backend "gcs" {
    prefix = "bootstrap"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
