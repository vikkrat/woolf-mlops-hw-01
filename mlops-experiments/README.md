# ДЗ №4: MLflow experiments і метрики у Grafana

Проєкт реалізує відстеження серії ML-експериментів: MLflow зберігає metadata у
PostgreSQL та artifacts у MinIO, а фінальні `accuracy` і `loss` передаються в
Prometheus PushGateway та переглядаються у Grafana. Усі кластерні сервіси
описані декларативно як Argo CD Applications.

## Архітектура

```text
train_and_push.py
  ├─ HTTP → MLflow Tracking Server :5000
  │          ├─ metadata → PostgreSQL :5432
  │          └─ artifacts → MinIO/S3 :9000
  └─ HTTP → PushGateway :9091
                       ↑ scrape
                    Prometheus → Grafana

Git lesson-9 → Argo CD → Kubernetes desired state
```

MLflow run - це одна зафіксована спроба навчання з конкретними параметрами,
метриками, тегами й artifacts. PostgreSQL зберігає структуровану історію runs;
MinIO зберігає більші бінарні об'єкти моделі. PushGateway потрібен тому, що
локальний training script є короткоживучим процесом і не має постійного `/metrics`
endpoint, який міг би scrape-ити Prometheus.

## Структура

```text
mlops-experiments/
├── argocd/
│   ├── applications/       # Argo CD Application CR для 5 компонентів
│   └── workloads/          # декларативні MinIO/PostgreSQL/MLflow ресурси
├── experiments/
│   └── train_and_push.py
├── best_model/             # з'являється після успішного запуску
├── tests/
├── assets/
├── .env.example
└── requirements.txt
```

## Розгортання через Argo CD

Перед початком EKS cluster та Argo CD мають бути доступні, а kubeconfig -
налаштований. Application-об'єкти створюються в `infra-tools`, workload-и - в
`application` і `monitoring`:

```bash
kubectl apply -f mlops-experiments/argocd/applications/

kubectl -n infra-tools get applications
kubectl -n application get pods,svc
kubectl -n monitoring get pods,svc,servicemonitors
```

Argo CD автоматично застосовує зміни з гілки `lesson-9`, виконує `selfHeal` та
`prune`. Сервіси мають тип `ClusterIP`, тому AWS Load Balancer не створюється.

## Локальний доступ через port-forward

Кожну команду запускайте в окремому CloudShell/terminal tab:

```bash
kubectl -n application port-forward svc/mlflow 5000:5000
kubectl -n application port-forward svc/minio 9000:9000
kubectl -n monitoring port-forward svc/pushgateway-prometheus-pushgateway 9091:9091
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Адреси після port-forward:

- MLflow: <http://127.0.0.1:5000>;
- MinIO API: <http://127.0.0.1:9000>;
- PushGateway: <http://127.0.0.1:9091>;
- Grafana: <http://127.0.0.1:3000> (`admin` / навчальний пароль із
  `monitoring.yaml`).

## Запуск експериментів

```bash
cd mlops-experiments
python -m venv .venv
source .venv/bin/activate        # Windows PowerShell: .venv\Scripts\Activate.ps1
pip install -r requirements.txt
cp .env.example .env             # Windows: Copy-Item .env.example .env
python experiments/train_and_push.py
```

Скрипт:

1. один раз робить deterministic stratified split Iris;
2. тренує чотири `LogisticRegression` з різними `C`/`max_iter`;
3. створює окремий MLflow run для кожної моделі;
4. логує parameters, `accuracy`, `loss`, tags та sklearn model artifact;
5. пушить `mlflow_accuracy` і `mlflow_loss` із label `run_id` у PushGateway;
6. вибирає найбільшу accuracy (при нічиїй - найменший loss);
7. завантажує artifact переможця з MinIO у `best_model/`.

## Перевірка MLflow

У MLflow UI відкрийте experiment `Iris Logistic Regression - lesson 9`.
Очікуються чотири runs. Для кожного доступні parameters `C`, `max_iter`,
`solver`, metrics `accuracy`/`loss`, tags і artifact `model`.

## Перевірка метрик у Grafana

Відкрийте **Grafana → Explore**, виберіть Prometheus datasource і виконайте:

```promql
mlflow_accuracy
```

```promql
mlflow_loss
```

Для табличного порівняння найкращої accuracy:

```promql
sort_desc(mlflow_accuracy)
```

PushGateway не є довготривалим сховищем: Prometheus scrape-ить його й формує
time series. Grouping key `run_id` зберігає окрему series для кожного run.

## Тести

```bash
python -m compileall experiments tests
pytest -q
```

## Безпека та контроль вартості

Це одноразове навчальне середовище: MinIO/PostgreSQL/Grafana використовують
`emptyDir`, а всі Services - `ClusterIP`. Demo credentials у маніфестах не можна
використовувати в production. Правильний production-підхід: External Secrets,
AWS Secrets Manager, persistent encrypted volumes, backup/restore та network
policies.

Порядок видалення після фіксації доказів:

1. видалити Applications/Argo CD;
2. видалити EKS і node groups;
3. видалити VPC, NAT Gateway та Elastic IP;
4. видалити всі версії Terraform state і S3 bucket;
5. виконати глобальний AWS cost-audit.

Фінальні докази та точні результати запуску додаються до `report.md` після
фактичної перевірки.

