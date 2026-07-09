variable "project_id" {
  description = "GCP project ID hosting the n8n infrastructure."
  type        = string
}

variable "region" {
  description = "Region for regional resources. Must stay one of GCP's Compute Engine Always Free e2-micro regions (us-west1/us-central1/us-east1)."
  type        = string
  default     = "us-west1"
}

variable "zone" {
  description = "Zone for the VM and its data disk."
  type        = string
  default     = "us-west1-b"
}

variable "domain" {
  description = "Public FQDN n8n is served on. Split into SUBDOMAIN/DOMAIN_NAME by the startup-script to match the existing docker-compose.yml env vars."
  type        = string
  # Starts pointed at the blue/green validation subdomain; change this
  # default (via a plain PR) to "n8n.u-rei.com" once Phase A validation
  # passes and it's time to cut over - see migrate-n8n-to-iac's tasks.md
  # section 8.
  default = "n8n-test.u-rei.com"
}

variable "ssl_email" {
  description = "Email address Traefik's ACME (Let's Encrypt) registration uses."
  type        = string
  default     = "byebyeearthjpn@gmail.com"
}

variable "generic_timezone" {
  description = "n8n GENERIC_TIMEZONE value."
  type        = string
  default     = "Asia/Tokyo"
}

variable "github_repo" {
  description = "Public GitHub repo (owner/repo) the VM clones at boot to get docker-compose.yml/base.yml."
  type        = string
}

variable "tailscale_tailnet" {
  description = "Tailscale tailnet identifier (e.g. example.ts.net or an org name). Same tailnet vaultwarden-ops operates in."
  type        = string
}

variable "tailscale_oauth_client_id" {
  description = "Tailscale OAuth client ID used by the tailscale Terraform provider."
  type        = string
  sensitive   = true
}

variable "tailscale_oauth_client_secret" {
  description = "Tailscale OAuth client secret used by the tailscale Terraform provider."
  type        = string
  sensitive   = true
}
