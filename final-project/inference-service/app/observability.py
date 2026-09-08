"""Метрики та структуровані JSON-логи для production спостережності."""

import json
import logging
import sys
import time
from collections.abc import Awaitable, Callable

from fastapi import Request, Response
from prometheus_client import Counter, Gauge, Histogram

REQUESTS = Counter(
    "inference_requests_total",
    "Кількість HTTP-запитів до inference API.",
    ["method", "path", "status"],
)
LATENCY = Histogram(
    "inference_request_duration_seconds",
    "Latency HTTP-запиту; histogram дозволяє рахувати p50 та p95.",
    ["method", "path"],
)
PREDICTIONS = Counter(
    "inference_predictions_total",
    "Кількість predictions за класом та версією моделі.",
    ["class_name", "model_version"],
)
MODEL_READY = Gauge(
    "inference_model_ready",
    "1, якщо model artifact перевірено й завантажено; інакше 0.",
)


class JsonFormatter(logging.Formatter):
    """Формує один валідний JSON-об'єкт на кожну подію для Loki."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for field in ("request_id", "path", "status", "latency_ms", "model_version"):
            value = getattr(record, field, None)
            if value is not None:
                payload[field] = value
        return json.dumps(payload, ensure_ascii=False)


def configure_logging() -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    logging.basicConfig(level=logging.INFO, handlers=[handler], force=True)


async def metrics_middleware(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    """Вимірює кожний запит незалежно від успіху endpoint-а."""

    started = time.perf_counter()
    response = await call_next(request)
    elapsed = time.perf_counter() - started
    route = request.scope.get("route")
    path = getattr(route, "path", request.url.path)
    REQUESTS.labels(request.method, path, str(response.status_code)).inc()
    LATENCY.labels(request.method, path).observe(elapsed)
    logging.getLogger("http").info(
        "request_completed",
        extra={
            "request_id": request.headers.get("x-request-id", "missing"),
            "path": path,
            "status": response.status_code,
            "latency_ms": round(elapsed * 1000, 3),
        },
    )
    return response
