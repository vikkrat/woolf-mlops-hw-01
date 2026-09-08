provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project    = var.project_name
      Owner      = "Viktoriia_Kratser"
      ManagedBy  = "Terraform"
      AutoDelete = "true"
    }
  }
}

data "aws_eks_cluster_auth" "this" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
