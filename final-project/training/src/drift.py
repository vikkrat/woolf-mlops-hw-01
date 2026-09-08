"""Periodic Evidently data-drift check exported to Prometheus Pushgateway."""

from __future__ import annotations

import os

from evidently import Dataset, Report
from evidently.presets import DataDriftPreset
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway
from sklearn.datasets import load_iris


def measure_drift() -> float:
    """Compares a stable reference slice with a recent production-like slice."""

    iris = load_iris(as_frame=True)
    frame = iris.frame.drop(columns=["target"])
    reference = Dataset.from_pandas(frame.iloc[:75])
    current = Dataset.from_pandas(frame.iloc[75:])
    result = Report([DataDriftPreset()]).run(reference, current)
    payload = result.dict()

    # Evidently API evolves, тому обходимо вкладений result без прив'язки до
    # позиції поля. Назви цільових метрик при цьому лишаються явними.
    stack: list[object] = [payload]
    while stack:
        node = stack.pop()
        if isinstance(node, dict):
            for key, value in node.items():
                if key in {"share_of_drifted_columns", "drift_share"}:
                    return float(value)
                stack.append(value)
        elif isinstance(node, list):
            stack.extend(node)
    return 0.0


def main() -> None:
    registry = CollectorRegistry()
    metric = Gauge("model_data_drift_score", "Evidently share of drifted input columns", registry=registry)
    metric.set(measure_drift())
    push_to_gateway(
        os.getenv("PUSHGATEWAY_URL", "pushgateway-prometheus-pushgateway.monitoring.svc:9091"),
        job="evidently-drift",
        registry=registry,
    )


if __name__ == "__main__":
    main()
