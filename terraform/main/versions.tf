terraform {
  required_version = ">= 1.6.0"

  backend "gcs" {
    # bucket is supplied at `terraform init` time via -backend-config,
    # using the state_bucket output from terraform/bootstrap.
    prefix = "n8n/main"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.39"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.17"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "tailscale" {
  tailnet             = var.tailscale_tailnet
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
}
