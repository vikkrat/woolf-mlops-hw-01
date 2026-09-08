variable "project_name" { type = string }
variable "aws_region" { type = string }
variable "cluster_name" { type = string }
variable "cluster_endpoint" { type = string }
variable "cluster_ca_data" { type = string }
variable "training_image" { type = string }
variable "artifact_bucket" { type = string }
variable "gitlab_project_path" { type = string }
variable "ecr_repository_arns" { type = list(string) }

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

data "archive_file" "lambda" {
  for_each    = toset(["validate", "finalize"])
  type        = "zip"
  source_file = "${path.root}/../step-functions/lambda/${each.key}.py"
  output_path = "${path.root}/.terraform/${each.key}.zip"
}

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "stage" {
  for_each         = data.archive_file.lambda
  function_name    = "${var.project_name}-${each.key}"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "${each.key}.lambda_handler"
  filename         = each.value.output_path
  source_code_hash = each.value.output_base64sha256
  timeout          = 15
  memory_size      = 128
  depends_on       = [aws_iam_role_policy_attachment.lambda_logs]
}

resource "aws_iam_role" "step_functions" {
  name = "${var.project_name}-step-functions"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "states.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "step_functions" {
  name = "training-orchestration"
  role = aws_iam_role.step_functions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = [for function in aws_lambda_function.stage : function.arn] },
      { Effect = "Allow", Action = ["eks:DescribeCluster"], Resource = "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}" }
    ]
  })
}

# EKS access entry maps the AWS role to an RBAC-scoped Kubernetes identity.
resource "aws_eks_access_entry" "step_functions" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.step_functions.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "step_functions" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.step_functions.arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
  access_scope {
    type       = "namespace"
    namespaces = ["mlops-system"]
  }
  depends_on = [aws_eks_access_entry.step_functions]
}

resource "aws_sfn_state_machine" "training" {
  name     = "${var.project_name}-training"
  role_arn = aws_iam_role.step_functions.arn
  type     = "STANDARD"
  definition = jsonencode({
    Comment = "Validate -> train in EKS -> evaluate/register -> finalize"
    StartAt = "ValidateRequest"
    States = {
      ValidateRequest = {
        Type       = "Task", Resource = "arn:${data.aws_partition.current.partition}:states:::lambda:invoke"
        Parameters = { FunctionName = aws_lambda_function.stage["validate"].arn, "Payload.$" = "$" }
        OutputPath = "$.Payload", Next = "TrainEvaluateRegister"
      }
      TrainEvaluateRegister = {
        Type = "Task", Resource = "arn:${data.aws_partition.current.partition}:states:::eks:runJob.sync"
        Parameters = {
          ClusterName          = var.cluster_name
          CertificateAuthority = var.cluster_ca_data
          Endpoint             = var.cluster_endpoint
          Namespace            = "mlops-system"
          LogOptions           = { RetrieveLogs = true }
          Job = {
            apiVersion = "batch/v1", kind = "Job"
            metadata   = { "name.$" = "States.Format('train-{}', $.git_sha)" }
            spec = {
              backoffLimit            = 1
              ttlSecondsAfterFinished = 600
              template = {
                metadata = { labels = { app = "model-training" } }
                spec = {
                  restartPolicy = "Never", serviceAccountName = "mlflow"
                  containers = [{
                    name = "trainer", image = var.training_image
                    env = [
                      { name = "MLFLOW_TRACKING_URI", value = "http://mlflow.mlops-system.svc.cluster.local:5000" },
                      { name = "ARTIFACT_BUCKET", value = var.artifact_bucket },
                      { name = "CI_COMMIT_SHA", "value.$" = "$.git_sha" }
                    ]
                    resources       = { requests = { cpu = "250m", memory = "256Mi" }, limits = { cpu = "1", memory = "1Gi" } }
                    securityContext = { allowPrivilegeEscalation = false, runAsNonRoot = true }
                  }]
                }
              }
            }
          }
        }
        ResultPath = "$.training", Next = "Finalize"
        Retry      = [{ ErrorEquals = ["States.TaskFailed"], IntervalSeconds = 10, MaxAttempts = 2, BackoffRate = 2 }]
      }
      Finalize = {
        Type       = "Task", Resource = "arn:${data.aws_partition.current.partition}:states:::lambda:invoke"
        Parameters = { FunctionName = aws_lambda_function.stage["finalize"].arn, "Payload.$" = "$" }
        OutputPath = "$.Payload", End = true
      }
    }
  })
  depends_on = [aws_iam_role_policy.step_functions, aws_eks_access_policy_association.step_functions]
}

resource "aws_iam_openid_connect_provider" "gitlab" {
  url             = "https://gitlab.com"
  client_id_list  = ["https://gitlab.com"]
  thumbprint_list = ["b3dd7606d2b5a8b4a13771dbecc9ee1cecafa38a"]
}

resource "aws_iam_role" "gitlab" {
  name = "${var.project_name}-gitlab-ci"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.gitlab.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "gitlab.com:aud" = "https://gitlab.com" }
        StringLike   = { "gitlab.com:sub" = "project_path:${var.gitlab_project_path}:ref_type:branch:ref:*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "gitlab" {
  name = "build-and-start-training"
  role = aws_iam_role.gitlab.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["states:StartExecution", "states:DescribeExecution"], Resource = [aws_sfn_state_machine.training.arn, "arn:${data.aws_partition.current.partition}:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:execution:${aws_sfn_state_machine.training.name}:*"] },
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      { Effect = "Allow", Action = ["eks:DescribeCluster"], Resource = "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}" },
      { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"], Resource = var.ecr_repository_arns }
    ]
  })
}

resource "aws_eks_access_entry" "gitlab" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.gitlab.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "gitlab" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.gitlab.arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
  access_scope {
    type       = "namespace"
    namespaces = ["mlops-system"]
  }
  depends_on = [aws_eks_access_entry.gitlab]
}

output "state_machine_arn" { value = aws_sfn_state_machine.training.arn }
output "gitlab_ci_role_arn" { value = aws_iam_role.gitlab.arn }
