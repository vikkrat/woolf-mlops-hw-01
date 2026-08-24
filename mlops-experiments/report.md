# Звіт про виконання ДЗ №4

Гілка: `lesson-9`  
AWS region: `eu-north-1`  
Дата перевірки: буде зафіксована після deployment.

## Реалізація

- MLflow Tracking Server - metadata в PostgreSQL, artifacts у MinIO;
- PushGateway - приймання фінальних метрик короткоживучого training job;
- Prometheus/Grafana - scrape, PromQL і візуалізація;
- Argo CD - декларативне розгортання та контроль drift;
- `train_and_push.py` - чотири runs, вибір переможця, download artifact.

## Фактичні докази

Секцію буде заповнено після реального запуску в EKS. Тут будуть скріншоти Argo
CD Applications, MLflow UI, Grafana Explore, terminal output і фінального AWS
cleanup audit.

