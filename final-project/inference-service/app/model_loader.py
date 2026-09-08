"""Безпечне завантаження immutable model artifact."""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Protocol

import joblib
import numpy as np
from sklearn.datasets import load_iris
from sklearn.linear_model import LogisticRegression


class Predictor(Protocol):
    """Мінімальний контракт, потрібний API від ML-моделі."""

    def predict(self, values: np.ndarray) -> np.ndarray: ...

    def predict_proba(self, values: np.ndarray) -> np.ndarray: ...


def sha256(path: Path) -> str:
    """Обчислює checksum потоково, не завантажуючи весь artifact у RAM."""

    digest = hashlib.sha256()
    with path.open("rb") as artifact:
        for chunk in iter(lambda: artifact.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _development_model() -> LogisticRegression:
    """Детермінований fallback лише для локального запуску та unit-тестів."""

    dataset = load_iris()
    return LogisticRegression(max_iter=300, random_state=42).fit(
        dataset.data, dataset.target
    )


def load_model(model_path: str, expected_sha256: str, environment: str) -> Predictor:
    """Завантажує модель лише після перевірки цілісності.

    У staging/production відсутність файла або checksum є фатальною помилкою:
    pod не стає Ready і не отримує трафік. Локальний режим має контрольований
    fallback, щоб розробка не залежала від S3/MLflow.
    """

    path = Path(model_path)
    if not path.exists():
        if environment == "local":
            return _development_model()
        raise RuntimeError(f"Model artifact is missing: {path}")

    if not expected_sha256:
        if environment != "local":
            raise RuntimeError("MLOPS_MODEL_SHA256 is required outside local mode")
    elif sha256(path) != expected_sha256.lower():
        raise RuntimeError("Model artifact SHA256 mismatch")

    return joblib.load(path)
