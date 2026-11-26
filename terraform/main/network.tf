# Uses the project's default auto-mode VPC; a personal single-VM deployment
# doesn't need a dedicated network. This is the same VPC vaultwarden-ops'
# VM runs in.
data "google_compute_network" "default" {
  name    = "default"
  project = var.project_id
}

resource "google_compute_firewall" "allow_web" {
  name    = "n8n-allow-web"
  project = var.project_id
  network = data.google_compute_network.default.self_link

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["n8n-server"]
}

# Deliberately no firewall rule opens port 22 (or any other port) to the
# public internet for this VM's tag. All administrative access happens over
# `tailscale ssh`, which tunnels through the Tailscale WireGuard interface
# rather than GCP's network stack, so no corresponding ingress rule is
# needed here.
#
# NOTE: GCP's legacy `default-allow-ssh` rule (no target tag, so it exposed
# port 22 on every VM in the project, vaultwarden's included) was disabled by
# hand on 2026-11-26 and is due to be deleted - it is not managed by any
# Terraform. See openspec's remove-default-allow-ssh change.

# n8n-deploy.yml reaches the VM via `gcloud compute ssh --tunnel-through-iap`
# (see add-n8n-deploy-pipeline's design.md), which - unlike `tailscale ssh` -
# actually forwards a tcp:22 packet into the VPC via IAP, so it needs its own
# ingress rule, scoped to IAP's documented source range. With
# `default-allow-ssh` gone this is what keeps both CI deploys and operator IAP
# SSH working.
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "n8n-allow-iap-ssh"
  project = var.project_id
  network = data.google_compute_network.default.self_link

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["n8n-server"]
}

resource "google_compute_address" "n8n" {
  name    = "n8n-static-ip"
  project = var.project_id
  region  = var.region

  labels = {
    app = "n8n"
  }
}
