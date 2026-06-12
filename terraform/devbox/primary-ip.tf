# The stable public IPv4 — the asset this whole config exists to protect.
#
# A primary IP that outlives the server is what makes rebuilds boring: the IP
# never changes, so ~/.ssh/config, ansible/inventory.ini, and known_hosts are
# static files — no more per-rebuild ssh-keygen -R / edit-config churn
# (docs/provisioning.md §2 used to be exactly that).
#
# Lifecycle inversion vs the server: the SERVER is disposable (destroy + apply
# is the rebuild flow), the IP is not. auto_delete=false keeps it alive while
# detached (~EUR0.50/mo only during that window; free while attached);
# prevent_destroy refuses a `terraform destroy` that would take it out.
resource "hcloud_primary_ip" "devbox" {
  name        = "${var.server_name}-ip"
  type        = "ipv4"
  auto_delete = false
  datacenter  = var.primary_ip_datacenter

  labels = {
    project = "devbox"
    managed = "terraform"
  }

  lifecycle {
    prevent_destroy = true
  }
}
