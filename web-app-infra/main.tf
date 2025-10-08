# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  owners      = ["amazon"]
  most_recent        = true
  include_deprecated = true

   filter {
    name   = "name"
    # This will match amzn2-ami-hvm-2.0.20240109.0-x86_64-gp2
    values = ["amzn2-ami-hvm-2.0.2024*.0-x86_64-gp2"] 
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

