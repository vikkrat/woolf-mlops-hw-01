# Це єдиний зв'язок між незалежними root modules: EKS читає outputs уже
# застосованого VPC state, а не викликає каталог ../vpc як дочірній module.
data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket       = var.state_bucket
    key          = var.vpc_state_key
    region       = var.aws_region
    use_lockfile = true
  }
}

