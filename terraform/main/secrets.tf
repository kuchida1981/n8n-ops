# Unlike vaultwarden-service, n8n's docker-compose.yml doesn't take any
# secret-valued environment variables today (no ADMIN_TOKEN/SMTP
# equivalent) - n8n's own encryptionKey and credentials live inside the
# migrated data volume itself, not as a Terraform-managed secret. The only
# secret this stack needs is the Tailscale auth key.
resource "google_secret_manager_secret" "tailscale_authkey" {
  project   = var.project_id
  secret_id = "n8n-tailscale-authkey"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "tailscale_authkey" {
  secret      = google_secret_manager_secret.tailscale_authkey.id
  secret_data = tailscale_tailnet_key.vm.key
}
