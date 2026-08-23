variable "aws_region" {
  description = "AWS region for the homework infrastructure."
  type        = string
  default     = "eu-central-1"
}

variable "name" {
  description = "Prefix used for VPC resources and tags."
  type        = string
  default     = "mlops-hw2"
}

variable "vpc_cidr" {
  description = "Private IPv4 CIDR allocated to the VPC."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "single_nat_gateway" {
  description = "One NAT Gateway is cheaper for a short-lived lab; false gives one per AZ."
  type        = bool
  default     = true
}

