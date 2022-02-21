resource "aws_vpc" "default" {
  cidr_block = "1.2.0.0/24"

  tags = merge({
    Name = "${var.environment}-${var.application_name}"
  }, var.tags)
}