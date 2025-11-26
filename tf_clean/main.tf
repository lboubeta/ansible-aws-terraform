terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.2.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}


# --- VPC ---
resource "aws_vpc" "test_vpc" {
  cidr_block = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge({ Name = "${var.name_prefix}-vpc" }, var.tags)
}

# --- Subnet (public by default) ---
resource "aws_subnet" "test_public_subnet" {
  vpc_id                  = aws_vpc.test_vpc.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = var.map_public_ip_on_launch
  availability_zone       = "${var.aws_region}${var.aws_az_suffix}"

  tags = merge({ Name = "${var.name_prefix}-public-subnet" }, var.tags)
}

# --- Internet Gateway & Public Route Table ---
resource "aws_internet_gateway" "test_igw" {
  vpc_id = aws_vpc.test_vpc.id
  tags   = merge({ Name = "${var.name_prefix}-igw" }, var.tags)
}

resource "aws_route_table" "test_public_rt" {
  vpc_id = aws_vpc.test_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.test_igw.id
  }

  tags = merge({ Name = "${var.name_prefix}-public-rt" }, var.tags)
}

resource "aws_route_table_association" "test_public_assoc" {
  subnet_id      = aws_subnet.test_public_subnet.id
  route_table_id = aws_route_table.test_public_rt.id
}

# --- Security Group ---
resource "aws_security_group" "test_sg" {
  name        = "${var.name_prefix}-sg"
  description = "Allow SSH and application ports"
  vpc_id      = aws_vpc.test_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.extra_ingress_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({ Name = "${var.name_prefix}-sg" }, var.tags)
}

# --- Key pair (public key from path) ---
resource "aws_key_pair" "test_key" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

# --- AMI lookup (Windows) ---
data "aws_ami" "windows_test" {
  most_recent = true
  owners = [var.win25_owner]

  filter {
    name   = "name"
    values = ["Windows_Server-2025-English-Full-Base-2025.11.12"]
  }
}

# --- EC2 instances ---
resource "aws_instance" "windows_test" {
  count                      = var.vm_count
  ami                        = coalesce(var.ami_id, data.aws_ami.windows_test.id)
  instance_type              = var.instance_type
  subnet_id                  = aws_subnet.test_public_subnet.id
  vpc_security_group_ids     = [aws_security_group.test_sg.id]
  associate_public_ip_address = true
  key_name                   = aws_key_pair.test_key.key_name

  tags = merge({ Name = format("%s_%02d", var.vm_name, count.index), Deployment = "terraform", Family = "windows" }, var.tags)

  user_data = var.user_data
}

# --- Outputs ---
output "public_ips" {
  value = aws_instance.windows_test[*].public_ip
}

output "ssh_connections" {
  value = [
    for i in range(var.vm_count) :
    format("ssh -i %s %s@%s", var.private_key_path, var.ssh_user, (
      aws_instance.windows_test[i].public_ip
    ))
  ]
}