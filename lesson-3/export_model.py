#!/usr/bin/env python3
"""Export a pretrained torchvision model to TorchScript.

The model (MobileNetV2, ImageNet weights) is loaded through the modern
`weights=...` API, switched to evaluation mode, traced with a dummy input
and stored as `model/model.pt`.

Usage:
    python3 export_model.py [--output model/model.pt]
"""

from __future__ import annotations

import argparse
from pathlib import Path

import torch
from torchvision.models import MobileNet_V2_Weights, mobilenet_v2

DEFAULT_OUTPUT = Path("model") / "model.pt"
INPUT_SHAPE = (1, 3, 224, 224)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export MobileNetV2 to TorchScript")
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"where to write the TorchScript archive (default: {DEFAULT_OUTPUT})",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output_path: Path = args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Сучасний torchvision API: об'єкт weights одночасно задає ваги,
    # правильний preprocessing і назви 1000 класів ImageNet.
    weights = MobileNet_V2_Weights.DEFAULT
    print(f"[export] weights      : {weights}")
    print(f"[export] categories   : {len(weights.meta['categories'])}")

    model = mobilenet_v2(weights=weights)
    # eval() вимикає Dropout і переводить BatchNorm на збережені статистики.
    # Без цього trace зафіксував би навчальну, а не inference-поведінку.
    model.eval()

    # trace записує операції, які модель виконує на прикладі тензора форми
    # [batch, channels, height, width] = [1, 3, 224, 224].
    dummy_input = torch.randn(*INPUT_SHAPE)

    with torch.no_grad():
        traced_model = torch.jit.trace(model, dummy_input)
        traced_model = torch.jit.freeze(traced_model)

        # Контроль якості експорту: eager-модель і TorchScript-граф повинні
        # давати практично однакові logits на тому самому вході.
        max_abs_diff = (model(dummy_input) - traced_model(dummy_input)).abs().max().item()

    print(f"[export] max |eager - traced| difference: {max_abs_diff:.3e}")

    traced_model.save(str(output_path))
    size_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"[export] saved TorchScript model -> {output_path} ({size_mb:.2f} MB)")


if __name__ == "__main__":
    main()
