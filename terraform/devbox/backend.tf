# Remote state in Cloudflare R2 (S3-compatible) — per the global doctrine
# (docs/secrets.md → "Global doctrine"): state never lives only on one machine,
# so a lost laptop/devbox never orphans the live infra; `terraform init`
# re-pulls it anywhere. Creds come from env (AWS_ACCESS_KEY_ID/SECRET, sourced
# from the gitignored .r2-backend.env — see .r2-backend.env.example), never
# committed.
#
# R2 quirks (same as tipso's backend): no AWS metadata endpoint, region "auto",
# path-style addressing, S3-native lockfile (no DynamoDB).
#
# BOOTSTRAP EXCEPTION — the `devbox-backup` bucket is created OUT-OF-BAND (by
# hand, EU jurisdiction, in the same Cloudflare account as tipso-backup), NOT by
# this Terraform: it stores Terraform's own state, so it must exist *before*
# Terraform runs. The state bucket sits *under* Terraform, not *in* it.
terraform {
  backend "s3" {
    bucket = "devbox-backup"
    key    = "terraform/devbox.tfstate"
    region = "auto"
    endpoints = {
      s3 = "https://fbc5bc4bfe835ba7165482b7c8f500ee.eu.r2.cloudflarestorage.com"
    }
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
