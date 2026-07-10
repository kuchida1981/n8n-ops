resource "google_compute_instance" "n8n" {
  name         = "n8n"
  project      = var.project_id
  zone         = var.zone
  machine_type = "e2-micro"
  tags         = ["n8n-server"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-13"
      size  = 20
      type  = "pd-balanced"
    }
  }

  attached_disk {
    source      = google_compute_disk.n8n_data.self_link
    device_name = "n8n-data"
  }

  network_interface {
    network = data.google_compute_network.default.self_link

    access_config {
      nat_ip = google_compute_address.n8n.address
    }
  }

  service_account {
    email  = google_service_account.vm_runtime.email
    scopes = ["cloud-platform"]
  }

  # Free hardening with no cost or capability trade-off for this workload.
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    startup-script = templatefile("${path.module}/templates/startup-script.sh.tftpl", {
      project_id       = var.project_id
      domain           = var.domain
      ssl_email        = var.ssl_email
      generic_timezone = var.generic_timezone
      github_repo      = var.github_repo
      ts_secret_id     = google_secret_manager_secret.tailscale_authkey.secret_id
    })

    # Lets the terraform-ci-n8n service account (granted roles/compute.osLogin
    # in bootstrap) SSH in via IAP tunnel using short-lived, IAM-issued keys -
    # used by n8n-deploy.yml to run `docker compose pull && up -d` after a
    # version bump. Project-wide OS Login defaults to disabled, so this must
    # be set explicitly per-instance.
    enable-oslogin = "TRUE"
  }

  depends_on = [
    google_secret_manager_secret_version.tailscale_authkey,
    google_secret_manager_secret_iam_member.tailscale_authkey_access,
  ]
}
