"""Конфігурація сервісу, що читається зі змінних середовища."""

from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Єдине типізоване джерело runtime-налаштувань.

    Секрети навмисно не мають production-значень за замовчуванням і не
    зберігаються в Git. У Kubernetes їх передає Secret/External Secrets.
    """

    model_config = SettingsConfigDict(env_prefix="MLOPS_", case_sensitive=False)

    service_name: str = "iris-inference"
    environment: str = "local"
    model_version: str = "development"
    model_path: str = "/models/model.joblib"
    model_sha256: str = ""
    requests_per_minute: int = 60


@lru_cache
def get_settings() -> Settings:
    """Кешуємо конфіг: один процес не перечитує env на кожний запит."""

    return Settings()
