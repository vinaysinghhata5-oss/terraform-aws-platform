provider "aws" {
  region = var.region

  # Hard guard: refuse to run if credentials point at the wrong account.
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = var.repository
      Owner       = var.owner
    }
  }
}
