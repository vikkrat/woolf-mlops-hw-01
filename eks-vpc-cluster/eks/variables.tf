variable "aws_region" {
  description = "AWS region; must match the VPC state region."
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "mlops-hw2"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version supported in the selected AWS region."
  type        = string
  default     = "1.33"
}

variable "state_bucket" {
  description = "S3 bucket containing the VPC Terraform state."
  type        = string
}

variable "vpc_state_key" {
  description = "Object key of the VPC Terraform state."
  type        = string
  default     = "homework-2/vpc/terraform.tfstate"
}

