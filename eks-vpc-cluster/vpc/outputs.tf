output "vpc_id" {
  description = "VPC ID consumed by the EKS root module."
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "Private subnet IDs used by EKS worker nodes."
  value       = module.vpc.private_subnets
}

