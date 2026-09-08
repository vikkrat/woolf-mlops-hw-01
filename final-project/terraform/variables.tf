variable "aws_region" {
  description = "AWS region для всіх ресурсів проєкту."
  type        = string
  default     = "eu-north-1"
}
variable "project_name" {
  type    = string
  default = "viktoriia-mlops-final"
}
variable "kubernetes_version" {
  description = "Підтримувана EKS-версія; перевірити перед apply."
  type        = string
  default     = "1.34"
}
variable "git_revision" {
  type    = string
  default = "final-project"
}
variable "gitlab_project_path" {
  type    = string
  default = "vikkrat/mlops-final-project"
}
variable "release_image_tag" {
  description = "Immutable 40-character Git commit SHA used for all images."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.release_image_tag))
    error_message = "release_image_tag must be a full lowercase 40-character Git SHA."
  }
}
variable "allowed_admin_cidr" {
  description = "CIDR оператора для EKS public endpoint, наприклад 203.0.113.10/32."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.allowed_admin_cidr)) && var.allowed_admin_cidr != "0.0.0.0/0"
    error_message = "Use a valid narrow CIDR; 0.0.0.0/0 is forbidden."
  }
}
