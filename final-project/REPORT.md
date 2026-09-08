# Звіт про виконання фінального проєкту

Авторка: **Viktoriia_Kratser**

## Реалізовано в коді

- [x] Єдиний Terraform root і модулі `vpc/eks/argocd/mlflow/monitoring/training`.
- [x] Namespaces `staging`, `production`, `mlops-system`, `monitoring`.
- [x] Деплої застосунків через ArgoCD, self-heal та prune.
- [x] MLflow Model Registry: run -> version -> Staging -> manual Production.
- [x] Canary 90/10 і Git rollback.
- [x] Pydantic validation, rate limit, RBAC design, checksum, audit events.
- [x] Prometheus metrics, Grafana dashboard, Loki logs, Evidently drift.
- [x] Unit tests, Ruff, Terraform/Helm validation і Trivy у GitLab CI.
- [x] README, RUNBOOK, ADR, threat model і AWS cleanup audit.

## Фактичний demo-trace

Цей розділ заповнюється лише реальними IDs і screenshots після тимчасового AWS
deployment. Placeholder не вважається доказом.

| Доказ | Фактичний ID/стан | Screenshot |
|---|---|---|
| GitLab pipeline | очікує запуску | `assets/01-gitlab-pipeline.png` |
| Step Functions graph | очікує запуску | `assets/02-step-functions.png` |
| EKS nodes Ready | очікує запуску | `assets/03-eks-nodes.png` |
| ArgoCD all Synced/Healthy | очікує запуску | `assets/04-argocd.png` |
| MLflow Model Version Production | очікує запуску | `assets/05-mlflow-registry.png` |
| Grafana active metrics | очікує запуску | `assets/06-grafana.png` |
| Canary 90/10 sample | очікує запуску | `assets/07-canary.png` |
| Terraform destroy + AWS zero audit | очікує запуску | `assets/08-aws-cleanup.png` |

## Definition of Done

Фінальна здача готова лише коли всі вісім рядків вище мають фактичні значення,
зображення читабельні, `terraform destroy` успішний, а cost audit повертає нулі.
