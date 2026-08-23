output "cluster_name" {
  description = "EKS cluster name for aws eks update-kubeconfig."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "node_groups" {
  description = "Created EKS managed node groups."
  value       = keys(module.eks.eks_managed_node_groups)
}

