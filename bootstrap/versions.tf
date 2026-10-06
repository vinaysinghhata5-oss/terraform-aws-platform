terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Chicken-and-egg: first apply uses local state, then uncomment and run
  # `terraform init -migrate-state` to move bootstrap state into the bucket it created.
  # backend "s3" {
  #   bucket       = "acme-tfstate-<ACCOUNT_ID>-us-east-1"
  #   key          = "bootstrap/terraform.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   kms_key_id   = "alias/terraform-state"
  #   use_lockfile = true
  # }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform-bootstrap"
    }
  }
}
