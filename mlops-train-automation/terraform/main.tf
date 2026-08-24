locals {
  lambda_functions = {
    validate = {
      description = "Валідація JSON-запиту на тренування"
      handler     = "validate.lambda_handler"
      archive     = "validate.zip"
    }
    log_metrics = {
      description = "Логування фінального результату workflow"
      handler     = "log_metrics.lambda_handler"
      archive     = "log_metrics.zip"
    }
  }
}

# Lambda приймає цю роль через sts:AssumeRole.
resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Мінімально необхідний managed policy: запис stdout/stderr Lambda у CloudWatch.
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "stage" {
  for_each = local.lambda_functions

  function_name    = "${var.name_prefix}-${replace(each.key, "_", "-")}"
  description      = each.value.description
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = each.value.handler
  filename         = "${path.module}/lambda/${each.value.archive}"
  source_code_hash = filebase64sha256("${path.module}/lambda/${each.value.archive}")
  timeout          = 15
  memory_size      = 128

  depends_on = [aws_iam_role_policy_attachment.lambda_logs]
}

# Step Functions має право викликати лише дві Lambda цього workflow.
resource "aws_iam_role" "step_functions" {
  name = "${var.name_prefix}-sfn-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "step_functions_invoke" {
  name = "invoke-workflow-lambdas"
  role = aws_iam_role.step_functions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = values(aws_lambda_function.stage)[*].arn
    }]
  })
}

resource "aws_sfn_state_machine" "training" {
  name     = "${var.name_prefix}-workflow"
  role_arn = aws_iam_role.step_functions.arn
  type     = "STANDARD"

  # Інтеграція arn:aws:states:::lambda:invoke повертає службовий envelope;
  # OutputPath залишає для наступного кроку тільки корисний Payload.
  definition = jsonencode({
    Comment = "Навчальний MLOps workflow: validate -> log_metrics"
    StartAt = "ValidateData"
    States = {
      ValidateData = {
        Type     = "Task"
        Resource = "arn:${data.aws_partition.current.partition}:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.stage["validate"].arn
          "Payload.$"  = "$"
        }
        OutputPath = "$.Payload"
        Retry = [{
          ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"]
          IntervalSeconds = 2
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
        Next = "LogMetrics"
      }
      LogMetrics = {
        Type     = "Task"
        Resource = "arn:${data.aws_partition.current.partition}:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.stage["log_metrics"].arn
          "Payload.$"  = "$"
        }
        OutputPath = "$.Payload"
        End        = true
      }
    }
  })
}

# GitLab видає job короткоживучий OIDC JWT. AWS перевіряє його без збереження
# довготривалих access keys у CI/CD variables.
resource "aws_iam_openid_connect_provider" "gitlab" {
  url             = "https://gitlab.com"
  client_id_list  = ["https://gitlab.com"]
  thumbprint_list = ["b3dd7606d2b5a8b4a13771dbecc9ee1cecafa38a"]
}

resource "aws_iam_role" "gitlab_ci" {
  name = "${var.name_prefix}-gitlab-ci-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.gitlab.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "gitlab.com:aud" = "https://gitlab.com"
        }
        StringLike = {
          "gitlab.com:sub" = "project_path:${var.gitlab_project_path}:ref_type:branch:ref:*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "gitlab_ci" {
  name = "start-training-workflow"
  role = aws_iam_role.gitlab_ci.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "states:StartExecution",
        "states:DescribeExecution"
      ]
      Resource = [
        aws_sfn_state_machine.training.arn,
        "arn:${data.aws_partition.current.partition}:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:execution:${aws_sfn_state_machine.training.name}:*"
      ]
    }]
  })
}

output "state_machine_arn" {
  description = "ARN для GitLab CI variable STATE_MACHINE_ARN."
  value       = aws_sfn_state_machine.training.arn
}

output "lambda_function_names" {
  value = { for key, function in aws_lambda_function.stage : key => function.function_name }
}

output "gitlab_ci_role_arn" {
  description = "ARN для GitLab CI variable AWS_ROLE_ARN."
  value       = aws_iam_role.gitlab_ci.arn
}
