variable "aws_region" {
  description = "AWS region для Lambda та Step Functions."
  type        = string
  default     = "eu-north-1"
}

variable "name_prefix" {
  description = "Префікс назв ресурсів цього домашнього завдання."
  type        = string
  default     = "mlops-train-automation"
}

variable "gitlab_project_path" {
  description = "Повний GitLab namespace/project для обмеження OIDC trust policy."
  type        = string
  default     = "vikkrat-group/mlops-train-automation"
}

variable "tags" {
  description = "Спільні tags для аудиту й безпечного видалення ресурсів."
  type        = map(string)
  default = {
    Project   = "mlops-homework-5"
    Owner     = "Viktoriia_Kratser"
    ManagedBy = "Terraform"
  }
}
