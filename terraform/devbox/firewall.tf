# Cloud firewall — network-edge enforcement of the posture in agents/AGENTS.md
# ("don't expose anything to the public internet; all inbound except SSH is
# firewalled; reach dev servers over Tailscale"). Packets are dropped before
# they reach the box; the on-box ufw (ansible hardening role) stays as the
# second, host-level layer.
#
# Hetzner default-denies inbound once any rule exists; outbound stays
# unrestricted (no egress rules = allow all out — Tailscale, apt, git need it).
# Tailscale's data plane is outbound-initiated (DERP fallback), so it needs NO
# inbound rule; dev servers are reached over the tailnet, never the public IP.
resource "hcloud_firewall" "devbox" {
  name = var.firewall_name

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "SSH (laptop + Ansible; also Tailscale-independent fallback)"
  }
}
