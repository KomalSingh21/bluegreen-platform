terraform {
  required_version = ">= 1.6"

  backend "s3" {
    # Replace with your actual values after running the bootstrap commands
    bucket         = "bluegreen-tfstate-669167971315"
    key            = "prod/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "bluegreen-tfstate-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      ManagedBy   = "terraform"
      Environment = "prod"
    }
  }
}
