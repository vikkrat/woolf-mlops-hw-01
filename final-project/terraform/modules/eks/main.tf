variable "project_name" { type = string }
variable "kubernetes_version" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "allowed_admin_cidrs" { type = list(string) }

module "this" {
  source                                   = "terraform-aws-modules/eks/aws"
  version                                  = "~> 21.0"
  name                                     = var.project_name
  kubernetes_version                       = var.kubernetes_version
  vpc_id                                   = var.vpc_id
  subnet_ids                               = var.private_subnet_ids
  endpoint_public_access                   = true
  endpoint_public_access_cidrs             = var.allowed_admin_cidrs
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true
  addons = {
    vpc-cni    = { before_compute = true, most_recent = true }
    kube-proxy = { most_recent = true }
    coredns    = { most_recent = true }
  }
  eks_managed_node_groups = {
    general = {
      instance_types = ["t3.medium"]
      ami_type       = "AL2023_x86_64_STANDARD"
      min_size       = 2
      max_size       = 3
      desired_size   = 2
      labels         = { workload = "general" }
    }
  }
}

output "cluster_name" { value = module.this.cluster_name }
output "cluster_endpoint" { value = module.this.cluster_endpoint }
output "cluster_ca_data" { value = module.this.cluster_certificate_authority_data }
output "oidc_provider_arn" { value = module.this.oidc_provider_arn }
output "oidc_provider_url" { value = module.this.cluster_oidc_issuer_url }
