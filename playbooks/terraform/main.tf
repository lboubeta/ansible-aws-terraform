
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "test/terraform.tfstate"
    region    = "eu-north-1"
    encrypt        = true    
    dynamodb_table = "test-tf-locks"  
    }
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

# --- AMI lookup (RHEL9 default) ---
data "aws_ami" "test_rhel9" {
  most_recent = true
  owners      = [var.rhel9_owner]

  filter {
    name   = "name"
    values = ["RHEL-9.*x86_64*"]
  }
}

# --- EC2 instances ---
resource "aws_instance" "test_vm" {
  count                      = var.vm_count
  ami                        = coalesce(var.ami_id, data.aws_ami.test_rhel9.id)
  instance_type              = var.instance_type
  subnet_id                  = aws_subnet.test_public_subnet.id
  vpc_security_group_ids     = [aws_security_group.test_sg.id]
  associate_public_ip_address = false
  key_name                   = aws_key_pair.test_key.key_name

  tags = merge({ Name = format("%s-vm-%02d", var.name_prefix, count.index) }, var.tags)

  user_data = var.user_data
}

# --- Optional Elastic IPs and association ---
resource "aws_eip" "test_eip" {
  count = var.create_public_ip ? var.vm_count : 0
  vpc   = true

  depends_on = [ aws_instance.test_vm ]
  tags = merge({ Name = format("%s-eip-%02d", var.name_prefix, count.index) }, var.tags)
}

resource "aws_eip_association" "test_eip_assoc" {
  count = var.create_public_ip ? var.vm_count : 0

  instance_id   = aws_instance.test_vm[count.index].id
  allocation_id = aws_eip.test_eip[count.index].id

  depends_on = [ aws_eip.test_eip, aws_instance.test_vm ]
}

# --- Optional Route53 records per instance ---
resource "aws_route53_record" "test_dns" {
  count   = var.create_public_ip && length(var.dns_zone_id) > 0 ? var.vm_count : 0
  zone_id = var.dns_zone_id
  name    = format("%s-vm-%02d.%s", var.name_prefix, count.index, var.dns_domain)
  type    = "A"
  ttl     = 300
  records = [ aws_eip.test_eip[count.index].public_ip ]

  depends_on = [ aws_eip_association.test_eip_assoc ]
}

# --- Outputs ---
output "public_ips" {
  value = var.create_public_ip ? aws_eip.test_eip[*].public_ip : aws_instance.test_vm[*].public_ip
}

output "ssh_connections" {
  value = [
    for i in range(var.vm_count) :
    format("ssh -i %s %s@%s", var.private_key_path, var.ssh_user, (
      var.create_public_ip ? aws_eip.test_eip[i].public_ip : aws_instance.test_vm[i].public_ip
    ))
  ]
}