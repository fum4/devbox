# Registers the laptop's public key in the Hetzner project so a fresh server
# accepts root SSH from the laptop on first boot (Ansible's entry point — the
# base role then creates fum4 and hardening disables root login). This is the
# devbox-dedicated laptop key (laptop.md §3), not the box's GitHub identity.
# public_key: take only the "type base64" fields, dropping any trailing comment
# in the .pub file (e.g. "hetzner-dev"). The key stored in Hetzner has no comment,
# so reading the file verbatim would force a needless replace of the key resource.
resource "hcloud_ssh_key" "devbox" {
  name       = var.ssh_key_name
  public_key = join(" ", slice(split(" ", trimspace(file(pathexpand(var.ssh_public_key_path)))), 0, 2))
}
