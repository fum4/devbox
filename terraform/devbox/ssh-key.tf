# Registers the laptop's public key in the Hetzner project so a fresh server
# accepts root SSH from the laptop on first boot (Ansible's entry point — the
# base role then creates fum4 and hardening disables root login). This is the
# devbox-dedicated laptop key (laptop.md §3), not the box's GitHub identity.
resource "hcloud_ssh_key" "devbox" {
  name       = var.ssh_key_name
  public_key = file(pathexpand(var.ssh_public_key_path))
}
