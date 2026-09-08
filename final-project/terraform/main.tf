module "vpc" {
  source       = "./modules/vpc"
  project_name = var.project_name
}

module "eks" {
  source              = "./modules/eks"
  project_name        = var.project_name
  kubernetes_version  = var.kubernetes_version
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  allowed_admin_cidrs = [var.allowed_admin_cidr]
}

module "mlflow" {
  source            = "./modules/mlflow"
  project_name      = var.project_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  git_revision      = var.git_revision
  depends_on        = [module.eks]
}

module "argocd" {
  source                   = "./modules/argocd"
  git_revision             = var.git_revision
  artifact_bucket          = module.mlflow.artifact_bucket
  inference_repository_url = module.mlflow.inference_repository_url
  mlflow_repository_url    = module.mlflow.mlflow_repository_url
  training_repository_url  = module.mlflow.training_repository_url
  release_image_tag        = var.release_image_tag
  inference_irsa_role_arn  = module.mlflow.inference_irsa_role_arn
  mlflow_irsa_role_arn     = module.mlflow.mlflow_irsa_role_arn
  depends_on               = [module.eks, module.mlflow]
}

module "monitoring" {
  source       = "./modules/monitoring"
  project_name = var.project_name
  depends_on   = [module.argocd]
}

module "training" {
  source              = "./modules/training"
  project_name        = var.project_name
  aws_region          = var.aws_region
  cluster_name        = module.eks.cluster_name
  cluster_endpoint    = module.eks.cluster_endpoint
  cluster_ca_data     = module.eks.cluster_ca_data
  training_image      = "${module.mlflow.training_repository_url}:${var.release_image_tag}"
  artifact_bucket     = module.mlflow.artifact_bucket
  ecr_repository_arns = module.mlflow.repository_arns
  gitlab_project_path = var.gitlab_project_path
  depends_on          = [module.argocd, module.mlflow]
}
