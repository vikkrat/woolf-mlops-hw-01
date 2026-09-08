variable "git_revision" { type = string }
variable "artifact_bucket" { type = string }
variable "inference_repository_url" { type = string }
variable "mlflow_repository_url" { type = string }
variable "training_repository_url" { type = string }
variable "release_image_tag" { type = string }
variable "inference_irsa_role_arn" { type = string }
variable "mlflow_irsa_role_arn" { type = string }

locals {
  repository = "https://github.com/vikkrat/woolf-mlops-hw-01.git"
  inference_parameters = [
    { name = "image.repository", value = var.inference_repository_url },
    { name = "stable.tag", value = var.release_image_tag },
    { name = "canary.tag", value = var.release_image_tag },
    { name = "serviceAccount.roleArn", value = var.inference_irsa_role_arn },
    { name = "stable.modelS3Uri", value = "s3://${var.artifact_bucket}/models/production/model.joblib" },
    { name = "canary.modelS3Uri", value = "s3://${var.artifact_bucket}/models/staging/model.joblib" }
  ]
  extra_objects = [
    {
      apiVersion = "argoproj.io/v1alpha1", kind = "Application"
      metadata   = { name = "iris-staging", namespace = "argocd" }
      spec = {
        project = "default"
        source = {
          repoURL = local.repository, targetRevision = var.git_revision
          path    = "final-project/helm/inference"
          helm    = { valueFiles = ["values.yaml", "values-staging.yaml"], parameters = local.inference_parameters }
        }
        destination = { server = "https://kubernetes.default.svc", namespace = "staging" }
        syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
      }
    },
    {
      apiVersion = "argoproj.io/v1alpha1", kind = "Application"
      metadata   = { name = "iris-production", namespace = "argocd" }
      spec = {
        project = "default"
        source = {
          repoURL = local.repository, targetRevision = var.git_revision
          path    = "final-project/helm/inference"
          helm    = { valueFiles = ["values.yaml", "values-production.yaml"], parameters = local.inference_parameters }
        }
        destination = { server = "https://kubernetes.default.svc", namespace = "production" }
        syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
      }
    },
    {
      apiVersion = "argoproj.io/v1alpha1", kind = "Application"
      metadata   = { name = "mlflow", namespace = "argocd" }
      spec = {
        project = "default"
        source = {
          repoURL = local.repository, targetRevision = var.git_revision, path = "final-project/helm/mlflow"
          helm = { parameters = [
            { name = "artifactBucket", value = var.artifact_bucket },
            { name = "serviceAccount.roleArn", value = var.mlflow_irsa_role_arn },
            { name = "image.repository", value = var.mlflow_repository_url },
            { name = "image.tag", value = var.release_image_tag }
          ] }
        }
        destination = { server = "https://kubernetes.default.svc", namespace = "mlops-system" }
        syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
      }
    },
    {
      apiVersion = "argoproj.io/v1alpha1", kind = "Application"
      metadata   = { name = "ingress-nginx", namespace = "argocd" }
      spec = {
        project = "default"
        source = {
          repoURL = "https://kubernetes.github.io/ingress-nginx"
          chart   = "ingress-nginx", targetRevision = "4.14.5"
          # Для короткого навчального стенда не створюємо AWS Load Balancer:
          # доступ до ingress робимо контрольованим kubectl port-forward.
          helm = { releaseName = "ingress-nginx", values = "controller:\n  service:\n    type: ClusterIP\n  metrics:\n    enabled: true\n" }
        }
        destination = { server = "https://kubernetes.default.svc", namespace = "ingress-nginx" }
        syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
      }
    },
    {
      apiVersion = "argoproj.io/v1alpha1", kind = "Application"
      metadata   = { name = "monitoring", namespace = "argocd" }
      spec = {
        project = "default"
        source = {
          repoURL = "https://prometheus-community.github.io/helm-charts"
          chart   = "kube-prometheus-stack", targetRevision = "77.5.0"
          helm    = { releaseName = "monitoring", values = "grafana:\n  service:\n    type: ClusterIP\nprometheus:\n  prometheusSpec:\n    retention: 6h\n    serviceMonitorSelectorNilUsesHelmValues: false\n" }
        }
        destination = { server = "https://kubernetes.default.svc", namespace = "monitoring" }
        # Великі CRD kube-prometheus-stack перевищують ліміт annotation
        # client-side apply, тому Argo CD атомарно замінює їх без цієї annotation.
        syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true", "Replace=true"] }
      }
    },
    {
      apiVersion = "argoproj.io/v1alpha1", kind = "Application"
      metadata   = { name = "loki", namespace = "argocd" }
      spec = {
        project = "default"
        source = {
          repoURL = "https://grafana.github.io/helm-charts", chart = "loki", targetRevision = "6.38.0"
          helm    = { releaseName = "loki", values = "deploymentMode: SingleBinary\nsingleBinary:\n  replicas: 1\nloki:\n  auth_enabled: false\n  commonConfig:\n    replication_factor: 1\n  storage:\n    type: filesystem\nchunksCache:\n  enabled: false\nresultsCache:\n  enabled: false\n" }
        }
        destination = { server = "https://kubernetes.default.svc", namespace = "monitoring" }
        syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
      }
    },
    {
      apiVersion = "argoproj.io/v1alpha1", kind = "Application"
      metadata   = { name = "promtail", namespace = "argocd" }
      spec = {
        project     = "default"
        source      = { repoURL = "https://grafana.github.io/helm-charts", chart = "promtail", targetRevision = "6.17.0", helm = { releaseName = "promtail", values = "config:\n  clients:\n    - url: http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push\n" } }
        destination = { server = "https://kubernetes.default.svc", namespace = "monitoring" }
        syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
      }
    },
    {
      apiVersion = "argoproj.io/v1alpha1", kind = "Application"
      metadata   = { name = "pushgateway", namespace = "argocd" }
      spec = {
        project     = "default"
        source      = { repoURL = "https://prometheus-community.github.io/helm-charts", chart = "prometheus-pushgateway", targetRevision = "3.4.0", helm = { releaseName = "pushgateway" } }
        destination = { server = "https://kubernetes.default.svc", namespace = "monitoring" }
        syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
      }
    },
    {
      apiVersion = "argoproj.io/v1alpha1", kind = "Application"
      metadata   = { name = "observability-addons", namespace = "argocd" }
      spec = {
        project = "default"
        source = {
          repoURL = local.repository, targetRevision = var.git_revision, path = "final-project/helm/observability-addons"
          helm    = { parameters = [{ name = "trainingImage", value = "${var.training_repository_url}:${var.release_image_tag}" }] }
        }
        destination = { server = "https://kubernetes.default.svc", namespace = "monitoring" }
        syncPolicy  = { automated = { prune = true, selfHeal = true }, syncOptions = ["CreateNamespace=true"] }
      }
    }
  ]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "8.3.1"
  namespace        = "argocd"
  create_namespace = true
  atomic           = true
  cleanup_on_fail  = true
  timeout          = 900
  wait             = true
  values = [yamlencode({
    server  = { service = { type = "ClusterIP" } }
    configs = { params = { "server.insecure" = true } }
  })]
}

# CRD Application/ApplicationSet з'являються лише після встановлення Argo CD.
# Тому GitOps-об'єкти створюємо окремим кроком з явною залежністю від Helm release.
resource "kubernetes_manifest" "gitops_application" {
  for_each = { for object in local.extra_objects : object.metadata.name => object }

  manifest   = each.value
  depends_on = [helm_release.argocd]
}
