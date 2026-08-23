variable "aws_region" {
  description = "AWS region containing the existing EKS cluster."
  type        = string
  default     = "eu-north-1"
}

variable "cluster_name" {
  description = "Name of the existing EKS cluster from homework 2."
  type        = string
  default     = "mlops-hw2"
}

variable "argocd_namespace" {
  description = "Namespace where Argo CD is installed."
  type        = string
  default     = "infra-tools"
}

variable "argocd_chart_version" {
  description = "Pinned argo-cd Helm chart version."
  type        = string
  default     = "10.4.0"
}

variable "gitops_repo_url" {
  description = "Public Git repository watched by the ApplicationSet."
  type        = string
  default     = "https://github.com/vikkrat/goit-argo.git"
}

variable "gitops_revision" {
  description = "Git revision watched by Argo CD."
  type        = string
  default     = "main"
}

