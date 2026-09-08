"""Швидкі unit-тести чистих допоміжних функцій training pipeline."""

from pathlib import Path

import numpy as np

from src.train_register import file_sha256, stable_dataset_hash


def test_dataset_hash_is_stable_and_content_sensitive() -> None:
    first = np.array([[1.0, 2.0]])
    target = np.array([0])
    assert stable_dataset_hash(first, target) == stable_dataset_hash(first.copy(), target.copy())
    second = np.array([[1.0, 3.0]])
    assert stable_dataset_hash(first, target) != stable_dataset_hash(second, target)


def test_file_sha256(tmp_path: Path) -> None:
    artifact = tmp_path / "model.bin"
    artifact.write_bytes(b"immutable-model")
    assert file_sha256(artifact) == "0d628a566fb2275a9f93481a271798445993104aa188e9436ac615c9cc741d49"
