# Provider auth. No token in any file: the hcloud provider natively reads the
# HCLOUD_TOKEN environment variable, which bin/devbox-tf injects after
# decrypting ansible/secrets/hetzner-token.age in memory (same model as the
# state backend's AWS_* creds). Never hardcode a secret in a committed .tf
# file, and never keep one as gitignored plaintext either — docs/secrets.md
# → "Global doctrine".
provider "hcloud" {}
