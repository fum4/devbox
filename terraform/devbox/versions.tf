# Pinned tool + provider versions — house convention (see tipso
# infra/terraform/versions.tf): a `terraform apply` months from now should
# resolve the EXACT same provider. The committed .terraform.lock.hcl freezes the
# precise version + checksums; these constraints are the human-readable
# floor/ceiling.
terraform {
  required_version = ">= 1.9"

  required_providers {
    # Hetzner Cloud — the server, its stable primary IP, firewall, SSH key.
    # Nothing else: the devbox has no public domain (Tailscale MagicDNS names
    # it), so no DNS/CDN providers; R2 is only the state *backend* (backend.tf),
    # not a managed resource.
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.65"
    }
  }
}
