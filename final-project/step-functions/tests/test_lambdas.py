"""Unit tests for the cheap orchestration Lambda handlers."""

import importlib.util
from pathlib import Path

import pytest


def load_handler(name: str):
    path = Path(__file__).parents[1] / "lambda" / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module.lambda_handler


def test_validate_accepts_a_real_git_sha() -> None:
    result = load_handler("validate")({"git_sha": "a" * 40, "source": "test"}, None)
    assert result == {"validated": True, "git_sha": "a" * 40, "source": "test"}


def test_validate_rejects_untrusted_value() -> None:
    with pytest.raises(ValueError):
        load_handler("validate")({"git_sha": "main; rm -rf /"}, None)


def test_finalize_returns_auditable_status() -> None:
    result = load_handler("finalize")({"git_sha": "b" * 40}, None)
    assert result["pipeline_status"] == "SUCCEEDED"
