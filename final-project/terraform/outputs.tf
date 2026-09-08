output "cluster_name" { value = module.eks.cluster_name }
output "artifact_bucket" { value = module.mlflow.artifact_bucket }
output "inference_repository_url" { value = module.mlflow.inference_repository_url }
output "training_repository_url" { value = module.mlflow.training_repository_url }
output "mlflow_repository_url" { value = module.mlflow.mlflow_repository_url }
output "step_functions_arn" { value = module.training.state_machine_arn }
output "gitlab_ci_role_arn" { value = module.training.gitlab_ci_role_arn }
output "estimated_hourly_cost_note" {
  value = "EKS control plane + EC2 + NAT are billable. Destroy immediately after evidence."
}
