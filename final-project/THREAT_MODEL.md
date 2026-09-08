# Threat model: одна сторінка

## Активи та межі довіри

Активи: training data, model artifacts, Model Registry metadata, AWS account,
CI identity та production endpoint. Межі: Internet -> Ingress -> FastAPI;
GitLab -> AWS STS; pod -> S3/MLflow; ArgoCD -> Kubernetes API.

## Основні загрози і контролі

| Загроза | Ризик | Контроль |
|---|---|---|
| Некоректний/ворожий JSON | crash, некоректний prediction | Pydantic types/ranges, `extra=forbid`, безпечні 4xx |
| Flooding endpoint | виснаження CPU/RAM | rate limit, ResourceQuota, pod limits, alerting |
| Підміна model artifact | довільний код/погана модель | private versioned S3, least-privilege IRSA, SHA256 до load |
| Компрометація CI credential | AWS takeover | GitLab OIDC, 15-хв STS, project-bound trust policy, no static keys |
| Несанкціонований deploy | production drift | ArgoCD GitOps, protected branch/manual promotion, RBAC |
| Видалення/тиха заміна registry model | втрата traceability | S3 versioning, audit JSON events у Loki/CloudWatch, Git SHA tags |
| Витік внутрішніх деталей | допомога атакувальнику | generic HTTP errors, no stack traces/secrets in response |

## RBAC

- `mlops-engineer`: повний доступ до `staging`, обмежений edit у `production`;
- `viewer`: read-only в усіх application namespaces;
- CI: namespace-scoped EKS Edit тільки в `mlops-system`;
- inference ServiceAccount: тільки `s3:GetObject*` для `models/*`;
- MLflow ServiceAccount: List/Get/Put artifacts, без `DeleteObject`.

Residual risk: in-process rate limit не є глобальним для багатьох replicas.
Production evolution - Redis-backed limit або ingress/WAF rate limiting.
