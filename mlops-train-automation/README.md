# ДЗ №5: автоматизований training workflow

Проєкт створює відтворюваний serverless workflow `ValidateData → LogMetrics`:
AWS Step Functions координує два послідовні кроки, кожен крок викликає окрему
Python Lambda, Terraform описує всю інфраструктуру, а GitLab CI запускає workflow
після push.

```text
Git push → GitLab CI train-model → StartExecution
                                      │
                                      ▼
                            Step Functions Standard
                              │ ValidateData
                              ▼
                         Lambda validate.py
                              │ validated JSON
                              ▼
                         Lambda log_metrics.py
                              │
                              ▼
                         SUCCEEDED + metrics
```

## Підготовка Lambda archives

Linux/macOS або Git Bash:

```bash
cd terraform/lambda
zip -j validate.zip validate.py
zip -j log_metrics.zip log_metrics.py
```

Windows PowerShell:

```powershell
Compress-Archive -Path terraform/lambda/validate.py -DestinationPath terraform/lambda/validate.zip -Force
Compress-Archive -Path terraform/lambda/log_metrics.py -DestinationPath terraform/lambda/log_metrics.zip -Force
```

## Terraform deployment

```bash
cd terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output -raw state_machine_arn
```

## Ручний запуск і перевірка

```bash
STATE_MACHINE_ARN="$(terraform output -raw state_machine_arn)"
EXECUTION_ARN="$(aws stepfunctions start-execution \
  --state-machine-arn "$STATE_MACHINE_ARN" \
  --name "manual-$(date +%s)" \
  --input '{"source":"manual","commit":"local-test"}' \
  --query executionArn --output text)"

aws stepfunctions describe-execution --execution-arn "$EXECUTION_ARN"
aws stepfunctions get-execution-history --execution-arn "$EXECUTION_ARN"
```

В AWS Console відкрийте **Step Functions → State machines →
mlops-train-automation-workflow → Executions**. Успішна execution повинна мати
статус `Succeeded`, а граф — два зелені кроки `ValidateData` і `LogMetrics`.

Приклад вхідного JSON:

```json
{"source":"gitlab-ci","commit":"a1b2c3d4"}
```

## GitLab CI

`.gitlab-ci.yml` має дві jobs. `validate-terraform` перевіряє formatting і
синтаксис Terraform. `train-model` використовує офіційний AWS CLI image,
виконується для push pipeline, формує унікальну execution name та передає
`source` і `$CI_COMMIT_SHORT_SHA` у Step Function.

У **GitLab → Settings → CI/CD → Variables** додайте masked/protected variables:

- `AWS_DEFAULT_REGION=eu-north-1`;
- `STATE_MACHINE_ARN` — значення `terraform output -raw state_machine_arn`;
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` і за потреби
  `AWS_SESSION_TOKEN` — лише якщо навчальне середовище не має OIDC.

Для production використовуйте GitLab OIDC та тимчасові AWS credentials замість
довготривалих access keys.

## Тести

```bash
python -m unittest discover -s tests -v
```

## Видалення та контроль вартості

Step Functions і Lambda недорогі, але після збирання доказів середовище все одно
видаляється:

```bash
cd terraform
terraform destroy
```

Після destroy перевірте відсутність state machines, Lambda та CloudWatch log
groups із префіксом `mlops-train-automation`. Не видаляйте Terraform state до
успішного завершення destroy.

## Докази перевірки

Фактична execution `manual-1787614242` завершилася за `0.716 s` зі статусом
`SUCCEEDED`. Обидва Task states (`ValidateData`, `LogMetrics`) мають події
`TaskSucceeded`, а фінальний output містить `pipeline_status=SUCCEEDED`, commit
`lesson-10`, `validated_records=1` і `validation_errors=0`.

![Успішна execution і повна послідовність подій](assets/01-step-functions-succeeded.png)

![Execution status в AWS Console](assets/02-aws-step-functions-graph.png)
