#!/usr/bin/env python3
"""Run image classification with the exported TorchScript model.

Usage:
    python3 app/inference.py example.jpg
    python3 app/inference.py example.jpg --model model/model.pt --top-k 3
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import torch
from PIL import Image
from torchvision.models import MobileNet_V2_Weights

DEFAULT_MODEL = Path("model") / "model.pt"
DEFAULT_TOP_K = 3


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="TorchScript image classification")
    parser.add_argument("image", type=Path, help="path to the input image")
    parser.add_argument(
        "--model",
        type=Path,
        default=DEFAULT_MODEL,
        help=f"path to the TorchScript model (default: {DEFAULT_MODEL})",
    )
    parser.add_argument(
        "--top-k",
        type=int,
        default=DEFAULT_TOP_K,
        help=f"how many predictions to print (default: {DEFAULT_TOP_K})",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if not args.image.is_file():
        print(f"[error] image not found: {args.image}", file=sys.stderr)
        return 1
    if not args.model.is_file():
        print(f"[error] model not found: {args.model}", file=sys.stderr)
        return 1

    # Один CPU-потік зменшує різницю через паралельний порядок обчислень і
    # робить порівняння fat/slim відтворюванішим.
    torch.set_num_threads(1)

    # Тут беруться лише metadata і стандартний preprocessing; самі ваги вже
    # знаходяться всередині model.pt, тому під час inference мережа не потрібна.
    weights = MobileNet_V2_Weights.DEFAULT
    preprocess = weights.transforms()
    categories = weights.meta["categories"]

    model = torch.jit.load(str(args.model), map_location="cpu")
    model.eval()

    # PIL читає файл; convert("RGB") гарантує рівно три канали навіть для PNG
    # з alpha-каналом або чорно-білого зображення.
    image = Image.open(args.image).convert("RGB")
    batch = preprocess(image).unsqueeze(0)

    # inference_mode() не створює граф autograd: менше пам'яті та накладних витрат.
    with torch.inference_mode():
        logits = model(batch)

    # Модель повертає logits (не ймовірності). softmax перетворює їх на числа
    # від 0 до 1 із сумою 1, а topk вибирає найімовірніші класи.
    probabilities = torch.softmax(logits, dim=1).squeeze(0)
    top_k = min(args.top_k, probabilities.numel())
    confidences, class_ids = torch.topk(probabilities, k=top_k)

    print(f"image : {args.image}")
    print(f"model : {args.model}")
    print(f"top-{top_k} predictions:")
    for rank, (class_id, confidence) in enumerate(
        zip(class_ids.tolist(), confidences.tolist()), start=1
    ):
        label = categories[class_id]
        print(f"  {rank}. class_id={class_id:<4d} confidence={confidence:.4f}  label={label}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
