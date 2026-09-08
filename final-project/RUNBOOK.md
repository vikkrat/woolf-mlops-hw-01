# RUNBOOK: експлуатація та інциденти

## 1. Як викотити нову модель

1. Push у default branch запускає pipeline.
2. Переконайтеся, що lint, tests, build, Trivy та training зелені.
3. У MLflow порівняйте candidate з current Production за accuracy/log loss.
4. Запустіть manual job `promote-production` з `MODEL_VERSION=N`.
5. Запишіть SHA256 і version у Helm values окремим Git commit.
6. В ArgoCD дочекайтеся `Synced/Healthy` спочатку для staging, потім production.
7. Згенеруйте 100 тестових запитів і перевірте приблизний розподіл 90/10.
8. Спостерігайте Grafana щонайменше 10 хвилин.

## 2. Як зробити rollback

1. Зупиніть збільшення canary weight.
2. Виконайте `python -m src.promote rollback --version PREVIOUS_GOOD_VERSION`.
3. Зробіть `git revert BAD_DEPLOYMENT_COMMIT && git push`.
4. Перевірте ArgoCD `Synced/Healthy`, pod readiness і model version у відповіді.
5. Зафіксуйте incident timeline та причину.

## 3. Grafana показує latency p95 > 0.5 s

1. Перевірити, чи alert стосується stable, canary або обох.
2. Зіставити latency з CPU throttling, RAM і restart count.
3. Перевірити Loki за `request_id` та `model_version`.
4. Якщо деградує тільки canary - weight `0` окремим Git commit або rollback.
5. Якщо обидві версії - тимчасово збільшити replicas/limits через Git і
   перевірити залежності; не змінювати pod вручну.

## 4. Evidently показує data drift

1. Перевірити, чи reference і current windows коректні та достатні за розміром.
2. Визначити ознаки з найбільшим drift, перевірити schema/data pipeline.
3. Не промоутити модель автоматично лише через drift.
4. Запустити контрольне тренування на схвалених свіжих даних.
5. Порівняти offline quality; promotion залишається окремим рішенням людини.

## 5. Error rate > 1%

1. Розділити HTTP 4xx (клієнтський input) і 5xx (сервісна помилка).
2. Для 5xx: `kubectl -n production get pods,events` і Loki JSON logs.
3. Перевірити checksum/download model init container.
4. Canary-only помилка -> негайний rollback; global -> перевірити S3/IAM/DNS.

## 6. MLflow або PostgreSQL недоступні

Inference продовжує працювати з уже завантаженим artifact. Нові training і
promotion зупиняються. Перевірити pods/events, Secret reference, IRSA та S3.
Не видаляти Model Version і не підміняти S3 object вручну.

## 7. Повне видалення інфраструктури

1. Зберегти screenshots і IDs execution/run/version.
2. `terraform -chdir=terraform plan -destroy -out=destroy.tfplan`.
3. Переглянути plan: target project має бути `viktoriia-mlops-final`.
4. `terraform -chdir=terraform apply destroy.tfplan`.
5. Запустити `scripts/aws-cost-audit.sh`.
6. Тільки після успішного destroy очистити versioned state bucket.

## Escalation policy

| Alert | Перший отримувач | Коли ескалувати | Наступний отримувач |
|---|---|---|---|
| Drift warning | MLOps engineer | 30 хв або quality падає | ML/Data owner |
| p95 warning | MLOps engineer | 15 хв | Service owner |
| Error rate critical | MLOps + service owner | негайно | Incident lead |
| Registry/audit anomaly | Security + MLOps | негайно | Incident lead |
