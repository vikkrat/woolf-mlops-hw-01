"""Перший етап workflow: структурна валідація вхідних даних тренування."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Перевіряє обов'язкові поля та передає нормалізовані дані далі.

    У реальному ML pipeline тут перевіряють схему, пропуски, діапазони значень,
    data drift і доступність dataset. Для навчального workflow достатньо
    контрольованої перевірки JSON-контракту.
    """

    print("Validating training request...")
    if not isinstance(event, dict):
        raise TypeError("Step Function input must be a JSON object")

    required_fields = ("source", "commit")
    missing = [name for name in required_fields if not event.get(name)]
    if missing:
        raise ValueError(f"Missing required fields: {', '.join(missing)}")

    return {
        "validation_status": "PASSED",
        "validated_at": datetime.now(timezone.utc).isoformat(),
        "source": str(event["source"]),
        "commit": str(event["commit"]),
    }
