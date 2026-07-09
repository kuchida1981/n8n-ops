# n8n's data (SQLite DB, encryptionKey/config, community nodes, binary
# data) lives on a disk that is independent of the VM's lifecycle. If the
# VM is ever destroyed and recreated (e.g. due to a machine-type change),
# this disk survives and is simply reattached, so no data is lost.
#
# Unlike vaultwarden-service, n8n-service keeps its docker-compose.yml
# volume declarations as named volumes (unchanged from n8n's own quickstart
# sample) rather than bind mounts. Independence from the VM's lifecycle is
# instead achieved by pointing Docker's own data-root at this disk's mount
# path (see the startup-script), so the named volumes' actual storage lives
# here without any compose file changes.
resource "google_compute_disk" "n8n_data" {
  name    = "n8n-data"
  project = var.project_id
  zone    = var.zone
  # pd-balanced (SSD-backed) rather than pd-standard (HDD-backed): SQLite
  # fsyncs on every write, and pd-standard's IOPS ceiling is low enough to
  # noticeably affect responsiveness even at this small scale.
  type = "pd-balanced"
  size = 10

  lifecycle {
    prevent_destroy = true
  }
}
