# Звіт про виконання ДЗ №4

Гілка: `lesson-9`  
AWS region: `eu-north-1`  
Дата перевірки: 25.08.2026.

## Реалізація

- MLflow Tracking Server - metadata в PostgreSQL, artifacts у MinIO;
- PushGateway - приймання фінальних метрик короткоживучого training job;
- Prometheus/Grafana - scrape, PromQL і візуалізація;
- Argo CD - декларативне розгортання та контроль drift;
- `train_and_push.py` - чотири runs, вибір переможця, download artifact.

## Фактичне розгортання

- створено EKS `mlops-hw4` у `eu-north-1`;
- три worker nodes перейшли у стан `Ready`;
- усі Argo CD Applications (`mlflow-minio`, `mlflow-postgres`,
  `mlflow-tracking`, `prometheus-pushgateway`, `monitoring`) отримали стани
  `Synced` та `Healthy`;
- MLflow `/health` повернув HTTP 200;
- MinIO job створив bucket `mlflow-artifacts`;
- PushGateway віддав по чотири series `mlflow_accuracy` і `mlflow_loss`;
- `pytest -q` завершився результатом `2 passed`.

## Результати експериментів

| Run ID | C | max_iter | accuracy | loss |
|---|---:|---:|---:|---:|
| `8ec9e8eda21d4d7993187bc4f67bd1ae` | 0.01 | 100 | 0.842105 | 0.669840 |
| `0655e3744c4b490abbdc19d17f4b025a` | 0.1 | 200 | 0.947368 | 0.373275 |
| `127cd3669c954495a3ae098d8b4d795f` | 1.0 | 300 | 0.947368 | 0.175673 |
| `caea7dd8bd2645b484f053dcf5b61bf7` | 10.0 | 500 | 0.947368 | **0.096578** |

Найкращий run — `caea7dd8bd2645b484f053dcf5b61bf7`. Три конфігурації
отримали однакову accuracy, тому скрипт правильно застосував другий критерій —
мінімальний loss. Artifact переможця було прочитано з MinIO та завантажено в
`best_model/model`.

## Докази

### EKS nodes

![Три EKS worker nodes Ready](assets/01-eks-worker-nodes-ready.png)

### MLflow, PostgreSQL і MinIO

![MLflow stack Running](assets/02-kubernetes-mlflow-stack-running.png)

### Навчання і best model

![Чотири runs і best model](assets/03-training-four-runs-best-model.png)

### PushGateway та тести

![Вісім metric series і 2 passed](assets/04-pushgateway-metrics-and-tests.png)

### Argo CD та monitoring stack

![Applications Synced/Healthy, workloads Running](assets/05-argocd-applications-and-workloads.png)

## Зауваження й виправлення під час перевірки

1. Argo CD repo-server потребував більше пам'яті для рендерингу Helm chart;
   limit збільшено до 768 MiB.
2. У MLflow 3.3.2 немає старого CLI-параметра `--allowed-hosts`; несумісний
   параметр прибрано.
3. Два `t3.small` nodes вичерпали Kubernetes pod slots, тому на час перевірки
   node group збільшено до трьох nodes. Після збирання доказів увесь EKS/VPC
   стек видаляється.

## Контроль вартості

Для UI-доказів створено лише один короткочасний Load Balancer. Після фіксації
доказів видаляються Load Balancer, EKS/node group, NAT Gateway, Elastic IP, VPC
та versioned S3 bucket зі state. Після цього виконується повторний AWS audit.
