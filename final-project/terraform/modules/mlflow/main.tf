variable "project_name" { type = string }
variable "oidc_provider_arn" { type = string }
variable "oidc_provider_url" { type = string }
variable "git_revision" { type = string }

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "${var.project_name}-artifacts-"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ecr_repository" "image" {
  for_each             = toset(["inference", "training", "mlflow"])
  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
  force_delete = true
}

resource "kubernetes_namespace_v1" "mlops" {
  metadata { name = "mlops-system" }
}

resource "random_password" "postgres" {
  length  = 28
  special = false
}

resource "kubernetes_secret_v1" "mlflow_backend" {
  metadata {
    name      = "mlflow-backend"
    namespace = kubernetes_namespace_v1.mlops.metadata[0].name
  }
  data = {
    POSTGRES_DB       = "mlflow"
    POSTGRES_USER     = "mlflow"
    POSTGRES_PASSWORD = random_password.postgres.result
  }
  type = "Opaque"
}

locals {
  oidc_host = replace(var.oidc_provider_url, "https://", "")
  subjects = {
    mlflow    = "system:serviceaccount:mlops-system:mlflow"
    inference = "system:serviceaccount:*:inference"
  }
}

resource "aws_iam_role" "workload" {
  for_each = local.subjects
  name     = "${var.project_name}-${each.key}-irsa"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "${local.oidc_host}:aud" = "sts.amazonaws.com" }
        StringLike   = { "${local.oidc_host}:sub" = each.value }
      }
    }]
  })
}

resource "aws_iam_role_policy" "mlflow" {
  name = "artifact-read-write-no-delete"
  role = aws_iam_role.workload["mlflow"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.artifacts.arn },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "inference" {
  name = "production-model-read-only"
  role = aws_iam_role.workload["inference"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:GetObjectVersion"]
      Resource = "${aws_s3_bucket.artifacts.arn}/models/*"
    }]
  })
}

output "artifact_bucket" { value = aws_s3_bucket.artifacts.id }
output "inference_repository_url" { value = aws_ecr_repository.image["inference"].repository_url }
output "training_repository_url" { value = aws_ecr_repository.image["training"].repository_url }
output "mlflow_repository_url" { value = aws_ecr_repository.image["mlflow"].repository_url }
output "repository_arns" { value = [for repository in aws_ecr_repository.image : repository.arn] }
output "inference_irsa_role_arn" { value = aws_iam_role.workload["inference"].arn }
output "mlflow_irsa_role_arn" { value = aws_iam_role.workload["mlflow"].arn }
