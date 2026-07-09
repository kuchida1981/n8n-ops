output "vm_external_ip" {
  description = "Static external IP to point the current domain's (n8n.u-rei.com or n8n-test.u-rei.com) A record at."
  value       = google_compute_address.n8n.address
}

output "vm_name" {
  description = "GCE instance name, used as the Tailscale hostname for `tailscale ssh`."
  value       = google_compute_instance.n8n.name
}
