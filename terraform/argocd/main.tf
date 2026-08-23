resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.argocd_namespace
  create_namespace = true

  atomic          = true
  cleanup_on_fail = true
  timeout         = 900
  wait            = true

  values = [file("${path.module}/values/argocd-values.yaml")]
}

resource "kubectl_manifest" "applicationset" {
  depends_on = [helm_release.argocd]

  yaml_body = templatefile("${path.module}/values/applicationset.yaml.tftpl", {
    argocd_namespace = var.argocd_namespace
    gitops_repo_url  = var.gitops_repo_url
    gitops_revision  = var.gitops_revision
  })

  wait             = true
  server_side_apply = true
}

