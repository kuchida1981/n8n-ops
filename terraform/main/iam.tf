# Runtime identity attached to the VM. This is intentionally a *different*
# service account from the one GitHub Actions impersonates (terraform-ci,
# created in terraform/bootstrap): the VM only ever needs to read its own
# secret, never to create/modify infrastructure or other secrets.
resource "google_service_account" "vm_runtime" {
  project      = var.project_id
  account_id   = "n8n-vm"
  display_name = "n8n VM runtime"
}

resource "google_secret_manager_secret_iam_member" "tailscale_authkey_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.tailscale_authkey.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm_runtime.email}"
}
