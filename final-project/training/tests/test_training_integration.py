"""Small end-to-end training run against an isolated local MLflow backend."""

from pathlib import Path

import mlflow

from src.train_register import train_and_register


def test_full_training_run_registers_staging_model(
    tmp_path: Path, monkeypatch
) -> None:
    tracking_uri = f"sqlite:///{(tmp_path / 'mlflow.db').as_posix()}"
    mlflow.set_tracking_uri(tracking_uri)
    monkeypatch.delenv("ARTIFACT_BUCKET", raising=False)
    monkeypatch.setenv("CI_COMMIT_SHA", "a" * 40)

    result = train_and_register()

    assert result["stage"] == "Staging"
    assert result["accuracy"] >= 0.90
    assert len(str(result["dataset_sha256"])) == 64
    assert len(str(result["model_sha256"])) == 64
