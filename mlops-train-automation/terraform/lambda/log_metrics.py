"""Другий етап workflow: формування й логування результату pipeline."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Логує результат валідації та повертає фінальний JSON workflow.

    CloudWatch автоматично збере stdout Lambda. У production цей етап можна
    замінити записом метрик у MLflow, Model Registry або monitoring backend.
    """

    if event.get("validation_status") != "PASSED":
        raise ValueError("Metrics must not be logged for unvalidated input")

    result = {
        "pipeline_status": "SUCCEEDED",
        "logged_at": datetime.now(timezone.utc).isoformat(),
        "source": event["source"],
        "commit": event["commit"],
        "metrics": {"validated_records": 1, "validation_errors": 0},
    }
    print(f"Logging pipeline result: {result}")
    return result
