output "argocd_namespace" {
  description = "Namespace containing the Argo CD installation."
  value       = var.argocd_namespace
}

output "argocd_server_service" {
  description = "ClusterIP service used for local port-forwarding."
  value       = "argocd-server"
}

output "gitops_repo_url" {
  description = "Repository watched by the ApplicationSet."
  value       = var.gitops_repo_url
}

output "ui_commands" {
  description = "Commands for opening the Argo CD UI and reading its initial password."
  value = {
    port_forward = "kubectl -n ${var.argocd_namespace} port-forward svc/argocd-server 8080:443"
    password     = "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode"
  }
}

