# Звіт про виконання ДЗ №5

Гілка: `lesson-10`  
Автор: `Viktoriia_Kratser`  
AWS region: `eu-north-1`

## Реалізовано

- дві Python Lambda з чітким JSON-контрактом;
- Step Functions Standard workflow `ValidateData → LogMetrics`;
- least-privilege IAM roles;
- повний Terraform deployment;
- GitLab CI jobs для Terraform validation і запуску workflow після push;
- unit tests для позитивного та помилкового сценаріїв.

## Фактичні докази

Terraform успішно створив `7` ресурсів: дві IAM roles, Lambda logging policy
attachment, inline Step Functions policy, дві Lambda та одну Standard Step
Function.

Ручна execution `manual-1787614242` отримала вхід:

```json
{"source":"manual-proof","commit":"lesson-10"}
```

та завершилася зі статусом `SUCCEEDED` за `0.716 s`. Execution history містить
два повні цикли `TaskStateEntered → TaskScheduled → TaskStarted → TaskSucceeded
→ TaskStateExited`, після чого — `ExecutionSucceeded`.

Фінальний результат:

```json
{
  "pipeline_status": "SUCCEEDED",
  "source": "manual-proof",
  "commit": "lesson-10",
  "metrics": {"validated_records": 1, "validation_errors": 0}
}
```

![CLI evidence: SUCCEEDED і два Task states](assets/01-step-functions-succeeded.png)

![AWS Console: execution details](assets/02-aws-step-functions-graph.png)

## GitLab CI

Приватний GitLab-проєкт:
`https://gitlab.com/vikkrat-group/mlops-train-automation`.

Push commit `6c5ae95b` автоматично створив pipeline `#2787444318`:

- `validate-terraform` — `Passed`;
- `train-model` — `Passed`;
- загальна тривалість — `49 s`;
- через GitLab OIDC отримано короткоживучі AWS STS credentials;
- запущено execution `train-6c5ae95b-2787444318`;
- фінальний статус AWS — `SUCCEEDED`.

![GitLab pipeline Passed](assets/03-gitlab-pipeline-passed.png)

![train-model Job succeeded](assets/04-gitlab-train-job-succeeded.png)

Одноразовий GitLab PAT із scope `write_repository`, використаний лише для
первинного push, одразу відкликано; локальну копію токена видалено. AWS access
keys не створювалися й не зберігалися в GitLab variables.

Фінальний AWS teardown audit додається після видалення Terraform-ресурсів.
