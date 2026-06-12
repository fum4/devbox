output "ipv4_address" {
  description = "The stable public IPv4 (the primary IP — survives rebuilds). What ~/.ssh/config and ansible/inventory.ini point at, forever."
  value       = hcloud_primary_ip.devbox.ip_address
}

output "ssh_root" {
  description = "First-boot access (fresh box, before Ansible's hardening disables root)."
  value       = "ssh -i ${trimsuffix(pathexpand(var.ssh_public_key_path), ".pub")} root@${hcloud_primary_ip.devbox.ip_address}"
}

output "next_steps" {
  description = "What to do after a rebuild apply."
  value       = <<-EOT

    Box '${hcloud_server.devbox.name}' is up on ${hcloud_primary_ip.devbox.ip_address} (stable — config files don't change).

    Fresh rebuild? Continue with docs/provisioning.md §3:
      1. ansible-playbook -i inventory.ini site.yml   (ansible_user=root first run)
      2. flip inventory to ansible_user=fum4, re-run for idempotency
      3. claude /login on the box, then per-project /remote-control

    Adopted/no-op apply? Nothing to do.
  EOT
}
