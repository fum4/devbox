# All inputs. The one secret is marked `sensitive` so Terraform redacts it in
# plan output and logs. Defaults encode the decisions in docs/terraform.md, so a
# normal apply only needs hcloud_token in terraform.tfvars.

variable "hcloud_token" {
  description = "Hetzner Cloud API token, Read & Write scope, in the devbox project."
  type        = string
  sensitive   = true
}

variable "server_name" {
  description = "Server name = hostname = SSH alias = Tailscale machine name. One name everywhere."
  type        = string
  default     = "devbox"
}

variable "server_type" {
  description = <<-EOT
    Hetzner server type. cx33 = x86, 4 vCPU / 8 GB / 80 GB, ~EUR6.49/mo — sized
    for parallel agent sessions + per-project Docker infra (see docs/hetzner.md
    "Recurring costs"). Resizing later is a console Rescale, not a Terraform
    concern (same IP/disk).
  EOT
  type        = string
  default     = "cx33"
}

variable "location" {
  description = "Hetzner datacenter region. hel1 (Helsinki) — reliable stock, ~35ms from Romania."
  type        = string
  default     = "hel1"
}

variable "primary_ip_datacenter" {
  description = <<-EOT
    Datacenter of the stable primary IP (primary IPs are datacenter-scoped, not
    region-scoped — "hel1-dc2" is hel1's only public DC). Must match where the
    server lands; only relevant when creating the IP fresh (on import it's read
    from the live resource).
  EOT
  type        = string
  default     = "hel1-dc2"
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
