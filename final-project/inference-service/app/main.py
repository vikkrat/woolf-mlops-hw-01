"""FastAPI application for versioned Iris model inference."""

from contextlib import asynccontextmanager
from dataclasses import dataclass

import numpy as np
from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from prometheus_client import make_asgi_app
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from app.model_loader import Predictor, load_model
from app.observability import MODEL_READY, PREDICTIONS, configure_logging, metrics_middleware
from app.schemas import IrisFeatures, PredictionResponse
from app.settings import get_settings

CLASS_NAMES = ("setosa", "versicolor", "virginica")
settings = get_settings()
limiter = Limiter(key_func=get_remote_address)


@dataclass
class Runtime:
    """Mutable runtime state, створений один раз під час startup."""

    model: Predictor | None = None


runtime = Runtime()


@asynccontextmanager
async def lifespan(_: FastAPI):
    """Fail-fast startup: несправна модель не повинна приймати трафік."""

    configure_logging()
    MODEL_READY.set(0)
    runtime.model = load_model(
        settings.model_path, settings.model_sha256, settings.environment
    )
    MODEL_READY.set(1)
    yield
    MODEL_READY.set(0)


app = FastAPI(
    title="Iris Production Inference API",
    version="1.0.0",
    lifespan=lifespan,
)
app.state.limiter = limiter
app.middleware("http")(metrics_middleware)
app.mount("/metrics", make_asgi_app())


@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(_: Request, __: RateLimitExceeded) -> JSONResponse:
    """Повертаємо безпечну помилку без внутрішнього stack trace."""

    return JSONResponse(status_code=429, content={"detail": "Rate limit exceeded"})


@app.exception_handler(RequestValidationError)
async def validation_handler(_: Request, error: RequestValidationError) -> JSONResponse:
    """Контракт завдання: невалідний input повертає HTTP 400 без stack trace."""

    safe_errors = [
        {"field": ".".join(str(part) for part in item["loc"][1:]), "type": item["type"]}
        for item in error.errors()
    ]
    return JSONResponse(status_code=400, content={"detail": "Invalid request", "errors": safe_errors})


@app.get("/health/live")
def liveness() -> dict[str, str]:
    """Процес живий; Kubernetes може його не перезапускати."""

    return {"status": "alive"}


@app.get("/health/ready")
def readiness() -> dict[str, str]:
    """Pod готовий лише коли модель реально завантажена."""

    if runtime.model is None:
        raise HTTPException(status_code=503, detail="Model is not ready")
    return {"status": "ready", "model_version": settings.model_version}


@app.post("/predict", response_model=PredictionResponse)
@limiter.limit(lambda: f"{settings.requests_per_minute}/minute")
def predict(request: Request, features: IrisFeatures) -> PredictionResponse:
    """Валідує JSON, виконує prediction і записує бізнес-метрику."""

    del request  # slowapi читає аргумент; бізнес-логіка його не потребує.
    if runtime.model is None:
        raise HTTPException(status_code=503, detail="Model is not ready")

    values = np.array(
        [[
            features.sepal_length,
            features.sepal_width,
            features.petal_length,
            features.petal_width,
        ]]
    )
    predicted_class = int(runtime.model.predict(values)[0])
    probabilities = [round(float(value), 6) for value in runtime.model.predict_proba(values)[0]]
    class_name = CLASS_NAMES[predicted_class]
    PREDICTIONS.labels(class_name, settings.model_version).inc()
    return PredictionResponse(
        prediction=predicted_class,
        class_name=class_name,
        probabilities=probabilities,
        model_version=settings.model_version,
    )
