# State bucket is created by ../../bootstrap in the dev account.
# S3 native locking (use_lockfile) replaces the DynamoDB lock table (Terraform >= 1.10).
terraform {
  backend "s3" {
    bucket       = "acme-tfstate-111111111111-us-east-1"
    key          = "platform/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "alias/terraform-state"
    use_lockfile = true
  }
}
