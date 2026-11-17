# Auth key the VM consumes at boot to join the tailnet unattended.
# `preauthorized = true` combined with the ACL's tagOwners entry (owned by
# the shared-infra repo u-rei-infra - see below) means no manual approval
# step is needed in the Tailscale admin console. `reusable = true` because
# the VM may be destroyed and recreated (e.g. a machine-type change); a
# one-time key would leave the replacement VM unable to join tailnet, and
# therefore unreachable via `tailscale ssh`. The key only ever tags a
# device as tag:n8n-server, and is only readable by that VM's own runtime
# service account, so the exposure from reuse is minimal.
#
# NOTE: this repo does NOT manage a `tailscale_acl` resource. The Tailscale
# API has no partial-update endpoint for the ACL policy file - it's always
# a whole-file overwrite - so two Terraform states both owning it means
# whichever applies last wins and silently drops the other's tags/rules.
# kuchida1981/u-rei-infra (terraform/tailscale) is the tailnet's sole ACL
# owner and already contains tag:n8n-server's tagOwners entry and ssh rule;
# if that tag is ever missing there, this resource fails with a 400 ("tags
# ... invalid or not permitted") rather than silently doing the wrong thing.
# Adding another tailnet-connected service means a PR to u-rei-infra first,
# not a content sync across repos. This repo's OAuth client holds only the
# Auth Keys scope (restricted to tag:n8n-server), not Policy File.
resource "tailscale_tailnet_key" "vm" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  tags          = ["tag:n8n-server"]
  expiry        = 7776000 # 90 days; rotate by re-applying before this lapses
}
