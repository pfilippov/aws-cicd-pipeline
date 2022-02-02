terraform {
  required_version = "~> 1.0"

  backend "s3" {
    encrypt        = true
    bucket         = var.tf_state_bucket_name
    key            = var.tf_state_bucket_key
    dynamodb_table = var.tf_state_dynamodb_table
    region         = var.aws_region
  }
}