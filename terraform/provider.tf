terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # ---- Remote backend + state locking ----
  # State is stored in S3 (durable, shared) and locked via a DynamoDB table so
  # two people/pipelines can't apply at once and corrupt it. Config values are
  # supplied at init time so no account-specific data is committed:
  #
  #   terraform init -backend-config=backend.hcl
  #
  # See backend.hcl.example and the README for the one-time bootstrap of the
  # bucket + lock table.
  backend "s3" {
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  # Every resource gets these tags automatically.
  default_tags {
    tags = local.common_tags
  }
}
