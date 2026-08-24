"""Навчання серії моделей, MLflow tracking та експорт метрик у PushGateway.

Один запуск скрипта створює кілька MLflow runs для однакового train/test split.
Це важливо: лише за незмінних даних коректно порівнювати вплив гіперпараметрів.
"""

from __future__ import annotations

import json
import os
import shutil
from dataclasses import asdict, dataclass
from pathlib import Path

import mlflow
import mlflow.sklearn
from dotenv import load_dotenv
from mlflow import MlflowClient
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway
from sklearn.datasets import load_iris
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, log_loss
from sklearn.model_selection import train_test_split


EXPERIMENT_NAME = "Iris Logistic Regression - lesson 9"
PROJECT_ROOT = Path(__file__).resolve().parents[1]
BEST_MODEL_DIR = PROJECT_ROOT / "best_model"


@dataclass(frozen=True)
class RunResult:
    """Мінімальний набір даних для порівняння завершених runs."""

    run_id: str
    c: float
    max_iter: int
    accuracy: float
    loss: float


def require_setting(name: str, default: str | None = None) -> str:
    """Повернути конфігурацію або зупинити запуск із зрозумілою помилкою."""

    value = os.getenv(name, default)
    if not value:
        raise RuntimeError(
            f"Не задано {name}. Скопіюйте .env.example у .env і виконайте "
            "port-forward відповідного сервісу."
        )
    return value


def publish_metrics(pushgateway_url: str, result: RunResult) -> None:
    """Записати метрики одного run в окрему grouping key PushGateway.

    Власний CollectorRegistry не додає службові Python-метрики. Мітка ``run_id``
    дозволяє Grafana показати всі запуски окремими series, а grouping key не дає
    наступному запуску перезаписати попередній.
    """

    registry = CollectorRegistry()
    label_names = ("run_id", "c", "max_iter")
    label_values = (result.run_id, str(result.c), str(result.max_iter))

    accuracy_gauge = Gauge(
        "mlflow_accuracy",
        "Accuracy моделі, зафіксована після завершення MLflow run",
        labelnames=label_names,
        registry=registry,
    )
    loss_gauge = Gauge(
        "mlflow_loss",
        "Log loss моделі, зафіксований після завершення MLflow run",
        labelnames=label_names,
        registry=registry,
    )
    accuracy_gauge.labels(*label_values).set(result.accuracy)
    loss_gauge.labels(*label_values).set(result.loss)

    push_to_gateway(
        pushgateway_url,
        job="mlflow_iris_experiments",
        grouping_key={"run_id": result.run_id},
        registry=registry,
        timeout=15,
    )


def select_best(results: list[RunResult]) -> RunResult:
    """Вибрати найбільшу accuracy; при нічиїй перевага меншому loss."""

    if not results:
        raise ValueError("Неможливо вибрати модель: список runs порожній")
    return max(results, key=lambda item: (item.accuracy, -item.loss))


def download_best_model(client: MlflowClient, best: RunResult) -> Path:
    """Завантажити саме MLflow artifact найкращого run у ``best_model/``."""

    if BEST_MODEL_DIR.exists():
        shutil.rmtree(BEST_MODEL_DIR)
    BEST_MODEL_DIR.mkdir(parents=True)

    # download_artifacts перевіряє весь шлях MLflow -> MinIO, а не копіює
    # локальний sklearn-об'єкт. Отже каталог є доказом працездатності artifact store.
    downloaded_path = Path(
        client.download_artifacts(best.run_id, "model", str(BEST_MODEL_DIR))
    )
    (BEST_MODEL_DIR / "best_run.json").write_text(
        json.dumps(asdict(best), indent=2, ensure_ascii=False), encoding="utf-8"
    )
    return downloaded_path


def main() -> None:
    """Провести експерименти, опублікувати метрики і зберегти переможця."""

    load_dotenv(PROJECT_ROOT / ".env")
    tracking_uri = require_setting("MLFLOW_TRACKING_URI", "http://127.0.0.1:5000")
    pushgateway_url = require_setting("PUSHGATEWAY_URL", "http://127.0.0.1:9091")
    mlflow.set_tracking_uri(tracking_uri)
    mlflow.set_experiment(EXPERIMENT_NAME)

    # Фіксований stratified split робить runs відтворюваними та порівнюваними.
    iris = load_iris()
    x_train, x_test, y_train, y_test = train_test_split(
        iris.data,
        iris.target,
        test_size=0.25,
        random_state=42,
        stratify=iris.target,
    )

    parameter_grid = [
        {"C": 0.01, "max_iter": 100},
        {"C": 0.1, "max_iter": 200},
        {"C": 1.0, "max_iter": 300},
        {"C": 10.0, "max_iter": 500},
    ]
    results: list[RunResult] = []

    for parameters in parameter_grid:
        with mlflow.start_run(
            run_name=f"C={parameters['C']}-iter={parameters['max_iter']}"
        ) as active_run:
            model = LogisticRegression(
                C=parameters["C"],
                max_iter=parameters["max_iter"],
                solver="lbfgs",
                random_state=42,
            )
            model.fit(x_train, y_train)
            predictions = model.predict(x_test)
            probabilities = model.predict_proba(x_test)
            result = RunResult(
                run_id=active_run.info.run_id,
                c=parameters["C"],
                max_iter=parameters["max_iter"],
                accuracy=float(accuracy_score(y_test, predictions)),
                loss=float(log_loss(y_test, probabilities)),
            )

            mlflow.log_params(
                {"C": result.c, "max_iter": result.max_iter, "solver": "lbfgs"}
            )
            mlflow.log_metrics({"accuracy": result.accuracy, "loss": result.loss})
            mlflow.set_tags(
                {"dataset": "iris", "homework": "lesson-9", "stage": "candidate"}
            )
            mlflow.sklearn.log_model(
                sk_model=model,
                name="model",
                input_example=x_test[:3],
            )
            results.append(result)

        # Метрики пушимо після закриття run: у MLflow вже гарантовано є фінальний стан.
        publish_metrics(pushgateway_url, result)
        print(
            f"run={result.run_id} C={result.c} max_iter={result.max_iter} "
            f"accuracy={result.accuracy:.4f} loss={result.loss:.4f}"
        )

    best = select_best(results)
    client = MlflowClient(tracking_uri=tracking_uri)
    client.set_tag(best.run_id, "stage", "best")
    downloaded = download_best_model(client, best)
    print(
        f"Найкращий run: {best.run_id}; accuracy={best.accuracy:.4f}; "
        f"loss={best.loss:.4f}; artifact={downloaded}"
    )


if __name__ == "__main__":
    main()

