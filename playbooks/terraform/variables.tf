variable "name_prefix" {
  description = "Prefix used for naming resources"
  type        = string
  default     = "test"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "aws_az_suffix" {
  description = "AZ suffix appended to region to form availability_zone (eg 'a')"
  type        = string
  default     = "a"
}

variable "cidr_block" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "Subnet CIDR block"
  type        = string
  default     = "10.0.1.0/24"
}

variable "map_public_ip_on_launch" {
  description = "Whether subnet auto-assigns public IPs"
  type        = bool
  default     = true
}

variable "vm_count" {
  description = "Number of instances to create"
  type        = number
  default     = 1

  validation {
    condition     = var.vm_count >= 1
    error_message = "vm_count must be >= 1"
  }
}

variable "instance_type" {
  description = "Instance type for EC2/GCP/Azure VMs"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "Optional AMI id override; leave empty to use AMI data lookup"
  type        = string
  default     = ""
}

variable "rhel9_owner" {
  description = "Owner ID used when looking up RHEL9 AMI"
  type        = string
  default     = "309956199498"
}

variable "key_name" {
  description = "SSH key pair name in AWS"
  type        = string
  default     = "deployer"
}

variable "public_key_path" {
  description = "Local path to public key file (used by aws_key_pair)"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "private_key_path" {
  description = "Local path to private key file (used in ssh command output)"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "ssh_user" {
  description = "Username for SSH connections (used in output strings and metadata)"
  type        = string
  default     = "cloud-user"
}

variable "create_public_ip" {
  description = "Allocate Elastic IPs for instances when true"
  type        = bool
  default     = true
}

variable "dns_domain" {
  description = "DNS domain used when creating per-instance records (eg example.com)"
  type        = string
  default     = ".mydomain.com"
}

variable "dns_zone_id" {
  description = "Route53 hosted zone id (eg ZXXXXXXXX). Leave empty to skip DNS record creation."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Map of tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "extra_ingress_rules" {
  description = "List of additional ingress rules to add to the security group"
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = []
}

variable "user_data" {
  description = "Instance user_data (cloud-init or shell script)"
  type        = string
  default     = <<-EOT
#!/bin/bash
echo "Sistema iniciado correctamente" > /root/startup.log

  EOT
}

# --- Backend / state store ---
variable "backend_s3_bucket" {
  description = "S3 bucket name to store Terraform state (backend)"
  type        = string
  default     = "my-terraform-state-bucket"
}

variable "backend_s3_key" {
  description = "S3 key (path) for the state file, e.g. \"path/to/terraform.tfstate\""
  type        = string
  default     = "test/terraform.tfstate"
}

variable "backend_region" {
  description = "Region for the S3 backend (defaults to aws_region)"
  type        = string
  default     = "eu-north-1"
}

variable "backend_encrypt" {
  description = "Enable server-side encryption for backend (S3)"
  type        = bool
  default     = true
}

variable "backend_dynamodb_table" {
  description = "DynamoDB table name to use for state locking (optional)"
  type        = string
  default     = "test-tf-locks"
}

variable "create_backend_resources" {
  description = "If true create the S3 bucket and optional DynamoDB table in this configuration (bootstrap caveat)"
  type        = bool
  default     = false
}

