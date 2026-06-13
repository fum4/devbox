# The devbox VPS itself — deliberately DISPOSABLE. Everything inside it is
# reconstructed by Ansible + chezmoi from this repo (docs/provisioning.md);
# everything durable lives in git, in ansible/secrets/*.age, or in R2. The
# rebuild flow is: destroy this resource, apply (new box, SAME primary IP),
# run the playbook.
#
# No user_data / cloud-init on purpose: Hetzner's debian-12 image already has
# everything Ansible's first run needs (python3, root's authorized_key via
# ssh_keys below). Configuration is Ansible's job — keeping cloud-init at zero
# keeps the TF/Ansible seam clean and the import of the hand-made box exact.
resource "hcloud_server" "devbox" {
  name         = var.server_name
  server_type  = var.server_type
  image        = var.server_image
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.devbox.id]
  firewall_ids = [hcloud_firewall.devbox.id]

  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.devbox.id
    ipv6_enabled = true # auto-assigned, unmanaged — rebuilds get a fresh one; nothing depends on it
  }

  labels = {
    project = "devbox"
    managed = "terraform"
  }

  lifecycle {
    # ssh_keys only seeds root's authorized_keys at CREATE time (Ansible owns
    # users/keys afterwards), and the image only matters at create — neither may
    # force a replace on a running box. NO prevent_destroy here: destroying the
    # server is the supported rebuild flow; the primary IP carries continuity.
    #
    # public_net is ignored on UPDATE for the same continuity reason — and it is
    # load-bearing: adding/altering this block on a *running* server makes the
    # hcloud provider power-cycle + detach/reassign the primary IP, and that
    # detach once DELETED the primary IP (the IPv4 was lost; a same-address
    # replacement had to be recreated by hand). ignore_changes does NOT affect
    # CREATE, so a rebuild still attaches the IP from config — we only refuse to
    # re-touch the network plumbing on an already-running box.
    ignore_changes = [ssh_keys, image, public_net]
  }
}
