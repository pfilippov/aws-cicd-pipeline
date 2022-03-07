resource "aws_vpc" "default" {
  cidr_block = var.vpc_cidr_block

  tags = merge({
    Name = "${var.environment}-${var.application_name}"
  }, var.tags)
}