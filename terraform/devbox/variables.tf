# All inputs. No secrets here — credentials arrive as environment variables,
# decrypted in memory from the age store by bin/devbox-tf (see providers.tf and
# docs/terraform.md). Defaults encode the decisions in docs/terraform.md, so a
# normal apply needs no input at all.

variable "server_name" {
  description = "Server name = OS hostname = SSH alias = Tailscale machine name. The live box is 'devbox-1' everywhere; keep it so (renaming to plain 'devbox' is a deliberate cross-cutting job — rDNS + OS hostname + Tailscale)."
  type        = string
  default     = "devbox-1"
}

variable "server_type" {
  description = <<-EOT
    Hetzner server type. cx43 = the live box's actual type (the old docs said
    cx33, which was wrong — adopting reality, NOT downsizing). Sized for parallel
    agent sessions + per-project Docker infra. A change here rescales the box
    in-place (brief poweroff, same IP; disk grows irreversibly unless keep_disk)
    — see docs/hetzner.md "Recurring costs". Downsizing is a deliberate act, not
    a drift fix.
  EOT
  type        = string
  default     = "cx43"
}

variable "location" {
  description = "Hetzner datacenter region. hel1 (Helsinki) — reliable stock, ~35ms from Romania."
  type        = string
  default     = "hel1"
}

variable "server_image" {
  description = "OS image. debian-12 — what every Ansible role + doc assumes."
  type        = string
  default     = "debian-12"
}

variable "ssh_public_key_path" {
  description = <<-EOT
    Path to the laptop's PUBLIC key that Hetzner installs as root's
    authorized_key on first boot (the same key Ansible then copies to fum4 —
    see laptop.md §3). The devbox-dedicated keypair, not the GitHub one.
  EOT
  type        = string
  default     = "~/.ssh/devbox_vps.pub"
}

variable "ssh_key_name" {
  description = "Name of the SSH key entry in the Hetzner project (hetzner.md §4 named it 'devbox')."
  type        = string
  default     = "devbox"
}

variable "firewall_name" {
  description = "Name of the cloud firewall attached to the server."
  type        = string
  default     = "devbox-fw"
}
