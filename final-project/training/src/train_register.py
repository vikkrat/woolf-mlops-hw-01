"""Train, evaluate and register a traceable Iris classifier in MLflow."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory

import joblib
import mlflow
import mlflow.sklearn
import boto3
from mlflow import MlflowClient
from sklearn.datasets import load_iris
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, log_loss
from sklearn.model_selection import train_test_split

REGISTERED_MODEL_NAME = os.getenv("REGISTERED_MODEL_NAME", "iris-classifier")
MIN_ACCURACY = float(os.getenv("MIN_ACCURACY", "0.90"))


def stable_dataset_hash(features: object, target: object) -> str:
    """Дає відтворюваний fingerprint саме тих даних, що бачив pipeline."""

    digest = hashlib.sha256()
    digest.update(memoryview(features))
    digest.update(memoryview(target))
    return digest.hexdigest()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as artifact:
        for chunk in iter(lambda: artifact.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def audit_event(action: str, **fields: object) -> None:
    """Структурована audit-подія; stdout збирається Loki/CloudWatch."""

    print(json.dumps({"event_type": "model_registry_audit", "action": action, **fields}))


def train_and_register() -> dict[str, object]:
    """Виконує один атомарний training run та переводить кандидата у Staging."""

    dataset = load_iris()
    dataset_version = stable_dataset_hash(dataset.data, dataset.target)
    x_train, x_test, y_train, y_test = train_test_split(
        dataset.data,
        dataset.target,
        test_size=0.25,
        random_state=42,
        stratify=dataset.target,
    )

    model = LogisticRegression(C=1.0, max_iter=300, random_state=42)
    git_sha = os.getenv("CI_COMMIT_SHA", os.getenv("GIT_SHA", "local"))

    mlflow.set_experiment(os.getenv("MLFLOW_EXPERIMENT_NAME", "iris-final-project"))
    with mlflow.start_run(run_name=f"train-{git_sha[:8]}") as run:
        model.fit(x_train, y_train)
        predictions = model.predict(x_test)
        probabilities = model.predict_proba(x_test)
        accuracy = float(accuracy_score(y_test, predictions))
        loss = float(log_loss(y_test, probabilities))

        mlflow.log_params({"C": 1.0, "max_iter": 300, "random_state": 42})
        mlflow.log_metrics({"accuracy": accuracy, "log_loss": loss})
        mlflow.set_tags(
            {
                "git_sha": git_sha,
                "dataset_sha256": dataset_version,
                "author": "Viktoriia_Kratser",
            }
        )

        if accuracy < MIN_ACCURACY:
            raise RuntimeError(
                f"Quality gate failed: accuracy={accuracy:.4f} < {MIN_ACCURACY:.4f}"
            )

        with TemporaryDirectory() as directory:
            artifact_path = Path(directory) / "model.joblib"
            joblib.dump(model, artifact_path)
            checksum = file_sha256(artifact_path)
            mlflow.log_artifact(str(artifact_path), artifact_path="immutable")
            mlflow.set_tag("model_sha256", checksum)

        # Спочатку зберігаємо модель як артефакт конкретного run. Реєстрацію
        # виконуємо окремим явним кроком нижче: так Registry отримує стабільний
        # URI runs:/..., а збій реєстрації не маскує успішне тренування.
        mlflow.sklearn.log_model(
            sk_model=model,
            artifact_path="model",
            input_example=x_test[:2],
        )

    client = MlflowClient()
    try:
        client.create_registered_model(REGISTERED_MODEL_NAME)
    except mlflow.exceptions.MlflowException as error:
        # RESOURCE_ALREADY_EXISTS є очікуваним для другого та наступних run.
        if "already exists" not in str(error).lower():
            raise
    version = client.create_model_version(
        name=REGISTERED_MODEL_NAME,
        source=f"runs:/{run.info.run_id}/model",
        run_id=run.info.run_id,
        tags={"git_sha": git_sha, "model_sha256": checksum},
    )
    client.transition_model_version_stage(
        name=REGISTERED_MODEL_NAME,
        version=version.version,
        stage="Staging",
        archive_existing_versions=False,
    )
    artifact_bucket = os.getenv("ARTIFACT_BUCKET")
    if artifact_bucket:
        # Кожна версія має окремий immutable key; staging є керованим pointer.
        downloaded = mlflow.artifacts.download_artifacts(
            run_id=run.info.run_id,
            artifact_path="immutable/model.joblib",
        )
        s3 = boto3.client("s3")
        metadata = {"sha256": checksum, "model-version": str(version.version)}
        s3.upload_file(
            downloaded,
            artifact_bucket,
            f"models/versions/{version.version}/model.joblib",
            ExtraArgs={"Metadata": metadata},
        )
        s3.copy_object(
            Bucket=artifact_bucket,
            Key="models/staging/model.joblib",
            CopySource={"Bucket": artifact_bucket, "Key": f"models/versions/{version.version}/model.joblib"},
            Metadata=metadata,
            MetadataDirective="REPLACE",
        )
    audit_event(
        "transition_to_staging",
        model=REGISTERED_MODEL_NAME,
        version=version.version,
        run_id=run.info.run_id,
        git_sha=git_sha,
    )
    return {
        "run_id": run.info.run_id,
        "registered_model_name": REGISTERED_MODEL_NAME,
        "model_version": version.version,
        "stage": "Staging",
        "accuracy": accuracy,
        "log_loss": loss,
        "git_sha": git_sha,
        "dataset_sha256": dataset_version,
        "model_sha256": checksum,
    }


if __name__ == "__main__":
    print(json.dumps(train_and_register(), indent=2))
