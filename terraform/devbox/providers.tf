# Provider auth. The token comes from a variable (set in terraform.tfvars,
# which is gitignored) — never hardcode a secret in a committed .tf file.
provider "hcloud" {
  token = var.hcloud_token
}
