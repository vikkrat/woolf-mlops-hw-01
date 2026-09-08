"""Контрактні тести API без зовнішніх AWS/MLflow залежностей."""

from fastapi.testclient import TestClient

from app.main import app


def test_predict_returns_versioned_probabilities() -> None:
    with TestClient(app) as client:
        response = client.post(
            "/predict",
            json={
                "sepal_length": 5.1,
                "sepal_width": 3.5,
                "petal_length": 1.4,
                "petal_width": 0.2,
            },
        )
    assert response.status_code == 200
    body = response.json()
    assert body["class_name"] == "setosa"
    assert len(body["probabilities"]) == 3
    assert abs(sum(body["probabilities"]) - 1.0) < 0.00001
    assert body["model_version"] == "development"


def test_invalid_input_is_rejected_without_internal_details() -> None:
    with TestClient(app) as client:
        response = client.post(
            "/predict",
            json={
                "sepal_length": "not-a-number",
                "sepal_width": 3.5,
                "petal_length": 1.4,
                "petal_width": 0.2,
                "unexpected": "blocked",
            },
        )
    assert response.status_code == 400
    assert "traceback" not in response.text.lower()


def test_health_and_metrics_are_available() -> None:
    with TestClient(app) as client:
        assert client.get("/health/live").status_code == 200
        assert client.get("/health/ready").status_code == 200
        metrics = client.get("/metrics/")
    assert metrics.status_code == 200
    assert "inference_model_ready" in metrics.text
