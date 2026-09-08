"""Публічний API-контракт inference-сервісу."""

from pydantic import BaseModel, ConfigDict, Field


class IrisFeatures(BaseModel):
    """Чотири числові ознаки Iris з реалістичними захисними межами."""

    model_config = ConfigDict(extra="forbid")

    sepal_length: float = Field(ge=3.5, le=8.5, examples=[5.1])
    sepal_width: float = Field(ge=1.5, le=5.0, examples=[3.5])
    petal_length: float = Field(ge=0.5, le=7.5, examples=[1.4])
    petal_width: float = Field(ge=0.05, le=3.0, examples=[0.2])


class PredictionResponse(BaseModel):
    """Стабільна відповідь, яку можуть споживати інші сервіси."""

    prediction: int
    class_name: str
    probabilities: list[float]
    model_version: str
