variable "project_name" { type = string }

# Коротке retention не дозволяє навчальним логам накопичувати вартість.
resource "aws_cloudwatch_log_group" "audit" {
  name              = "/mlops/${var.project_name}/audit"
  retention_in_days = 7
}

output "audit_log_group" { value = aws_cloudwatch_log_group.audit.name }
