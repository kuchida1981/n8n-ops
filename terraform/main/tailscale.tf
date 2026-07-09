# Auth key the VM consumes at boot to join the tailnet unattended.
# `preauthorized = true` combined with the ACL's tagOwners entry below
# means no manual approval step is needed in the Tailscale admin console.
# `reusable = true` because the VM may be destroyed and recreated (e.g. a
# machine-type change); a one-time key would leave the replacement VM
# unable to join tailnet, and therefore unreachable via `tailscale ssh`.
# The key only ever tags a device as tag:n8n-server, and is only readable
# by that VM's own runtime service account, so the exposure from reuse is
# minimal.
resource "tailscale_tailnet_key" "vm" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  tags          = ["tag:n8n-server"]
  expiry        = 7776000 # 90 days; rotate by re-applying before this lapses
}

# WARNING: `tailscale_acl` manages the tailnet's *entire* ACL policy file as
# a single resource, and this tailnet is already managed the same way by a
# SEPARATE Terraform state: vaultwarden-ops' `terraform/main/tailscale.tf`.
# Two independent Terraform states both owning this resource means whichever
# repo applies last "wins" and silently overwrites the other's tags/rules
# unless the ACL content here is kept as a superset of both.
#
# The policy below is vaultwarden-ops' current policy (tag:vaultwarden-server
# tagOwners + its ssh rule) with tag:n8n-server's tagOwners and ssh rule
# added alongside it. Before applying, re-check
# https://login.tailscale.com/admin/acl/file for any drift against
# vaultwarden-ops' tailscale.tf (e.g. a rule added there since this file was
# last written) and fold it in here too - see migrate-n8n-to-iac's
# design.md ("Tailscale ACLの2リポジトリ間管理") and tasks.md 4.2-4.3.
resource "tailscale_acl" "this" {
  # The provider refuses to blindly clobber a hand-edited, non-default ACL
  # (safety guard: "You are trying to overwrite a non-default policy").
  # That's expected here: this tailnet's policy already has
  # vaultwarden-ops' custom entries applied, and the content below is
  # reviewed to be a superset of that, so overwriting it is intentional.
  overwrite_existing_content = true

  acl = jsonencode({
    tagOwners = {
      "tag:vaultwarden-server" = ["autogroup:admin"]
      "tag:n8n-server"         = ["autogroup:admin"]
    }
    acls = [
      {
        action = "accept"
        src    = ["*"]
        dst    = ["*:*"]
      }
    ]
    ssh = [
      {
        action = "check"
        src    = ["autogroup:admin"]
        dst    = ["tag:vaultwarden-server"]
        users  = ["autogroup:nonroot", "root"]
      },
      {
        action = "check"
        src    = ["autogroup:admin"]
        dst    = ["tag:n8n-server"]
        users  = ["autogroup:nonroot", "root"]
      }
    ]
  })
}
