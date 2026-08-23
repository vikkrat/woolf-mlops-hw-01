data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # EKS потребує щонайменше дві AZ. slice бере перші дві доступні в регіоні.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  common_tags = {
    Project    = var.name
    ManagedBy  = "Terraform"
    Homework   = "2"
    AutoDelete = "true"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets  = [for index, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, index)]
  private_subnets = [for index, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, index + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_support   = true
  enable_dns_hostnames = true

  # Ці tags дозволяють Kubernetes load balancer controller розрізняти
  # public і private subnets.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

