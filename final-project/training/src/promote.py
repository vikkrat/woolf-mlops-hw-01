"""Explicit, auditable Staging -> Production promotion and rollback."""

from __future__ import annotations

import argparse
import json
import os

import boto3
from mlflow import MlflowClient

from src.train_register import REGISTERED_MODEL_NAME, audit_event


def promote(version: str) -> None:
    """Архівує стару Production і атомарно просуває перевіреного кандидата."""

    client = MlflowClient()
    candidate = client.get_model_version(REGISTERED_MODEL_NAME, version)
    if candidate.current_stage != "Staging":
        raise RuntimeError(
            f"Version {version} is {candidate.current_stage}, expected Staging"
        )
    client.transition_model_version_stage(
        name=REGISTERED_MODEL_NAME,
        version=version,
        stage="Production",
        archive_existing_versions=True,
    )
    bucket = os.environ["ARTIFACT_BUCKET"]
    s3 = boto3.client("s3")
    source_key = f"models/versions/{version}/model.joblib"
    metadata = s3.head_object(Bucket=bucket, Key=source_key)["Metadata"]
    s3.copy_object(
        Bucket=bucket,
        Key="models/production/model.joblib",
        CopySource={"Bucket": bucket, "Key": source_key},
        Metadata=metadata,
        MetadataDirective="REPLACE",
    )
    audit_event(
        "promote_to_production",
        model=REGISTERED_MODEL_NAME,
        version=version,
        actor=os.getenv("GITLAB_USER_LOGIN", "local-operator"),
        git_sha=os.getenv("CI_COMMIT_SHA", "local"),
    )


def rollback(version: str) -> None:
    """Повертає в Production відому справну версію однією командою."""

    client = MlflowClient()
    client.get_model_version(REGISTERED_MODEL_NAME, version)
    client.transition_model_version_stage(
        name=REGISTERED_MODEL_NAME,
        version=version,
        stage="Production",
        archive_existing_versions=True,
    )
    bucket = os.environ["ARTIFACT_BUCKET"]
    s3 = boto3.client("s3")
    source_key = f"models/versions/{version}/model.joblib"
    metadata = s3.head_object(Bucket=bucket, Key=source_key)["Metadata"]
    s3.copy_object(
        Bucket=bucket,
        Key="models/production/model.joblib",
        CopySource={"Bucket": bucket, "Key": source_key},
        Metadata=metadata,
        MetadataDirective="REPLACE",
    )
    audit_event(
        "rollback_to_production",
        model=REGISTERED_MODEL_NAME,
        version=version,
        actor=os.getenv("GITLAB_USER_LOGIN", "local-operator"),
        git_sha=os.getenv("CI_COMMIT_SHA", "local"),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("promote", "rollback"))
    parser.add_argument("--version", required=True)
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    {"promote": promote, "rollback": rollback}[args.action](args.version)
    print(json.dumps({"status": "ok", "action": args.action, "version": args.version}))
