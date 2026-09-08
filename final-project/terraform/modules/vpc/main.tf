variable "project_name" { type = string }

data "aws_availability_zones" "available" { state = "available" }

locals { azs = slice(data.aws_availability_zones.available.names, 0, 2) }

module "this" {
  source          = "terraform-aws-modules/vpc/aws"
  version         = "~> 6.0"
  name            = var.project_name
  cidr            = "10.42.0.0/16"
  azs             = local.azs
  private_subnets = [for index, _ in local.azs : cidrsubnet("10.42.0.0/16", 8, index)]
  public_subnets  = [for index, _ in local.azs : cidrsubnet("10.42.0.0/16", 8, index + 10)]

  # Один NAT дешевший для навчального стенду; це свідомий компроміс HA/вартості.
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_support   = true
  enable_dns_hostnames = true
  public_subnet_tags   = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags  = { "kubernetes.io/role/internal-elb" = "1" }
}

output "vpc_id" { value = module.this.vpc_id }
output "private_subnet_ids" { value = module.this.private_subnets }
