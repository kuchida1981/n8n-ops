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
# NOTE: the GCP project also has a legacy `default-allow-ssh` firewall rule
# that is not scoped to any target tag, and therefore still exposes port 22
# network-wide (affecting this VM and vaultwarden's alike) regardless of the
# rule below. Removing that legacy rule is out of scope for this change -
# see the migrate-n8n-to-iac proposal's roadmap notes.

resource "google_compute_address" "n8n" {
  name    = "n8n-static-ip"
  project = var.project_id
  region  = var.region
}
