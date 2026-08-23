# Lesson 3 — Containerized ML inference: fat vs slim Docker images

Homework #1 for the **MLOps CI/CD** course (topics *"Linux & Bash scripting"* and
*"Containerization of ML models"*).

A pretrained **MobileNetV2** is exported to **TorchScript** and served by a small
inference script. The same application is packaged into two Docker images —
a deliberately heavy one (`Dockerfile.fat`) and an optimized multi-stage one
(`Dockerfile.slim`) — and the two are compared in [`report.md`](report.md).

---

## 1. Requirements

| Component | Version | Notes |
|---|---|---|
| Docker Engine | 20.10+ | Docker Desktop on Windows/macOS |
| Docker Compose | **V2** (`docker compose`) | checked by the setup script |
| Python | **3.13+** | only needed to run the code outside Docker |
| pip | any recent | |
| torch / torchvision / pillow | see [`requirements.txt`](requirements.txt) | CPU-only wheels |

Both images are pinned to Python 3.13: `python:3.13` (fat) and
`python:3.13-slim` (slim).

---

## 2. Project structure

```
lesson-3/
├── app/
│   └── inference.py            # TorchScript inference, prints top-3 predictions
├── model/
│   └── model.pt                # TorchScript model (produced by export_model.py)
├── scripts/
│   ├── install_dev_tools.sh    # environment check / preparation, writes install.log
│   └── collect_metrics.sh      # builds both images and collects all report numbers
├── export_model.py             # MobileNetV2 -> torch.jit.trace -> model/model.pt
├── requirements.txt            # torch / torchvision / pillow (pinned, CPU wheels)
├── Dockerfile.fat              # single-stage, python:3.13, unoptimized baseline
├── Dockerfile.slim             # multi-stage, python:3.13-slim, optimized runtime
├── .dockerignore               # keeps .git, caches, venvs, logs out of the context
├── example.jpg                 # sample input image
├── report.md                   # fat vs slim comparison and analysis
└── README.md
```

---

## 3. Quick start

Everything below is run from the `lesson-3/` directory.

### 3.1 Prepare the environment

```bash
bash scripts/install_dev_tools.sh
```

The script checks Docker, Docker Compose V2, Python ≥ 3.13, pip and the Python
packages, installs what is missing, and appends a timestamped report to
`install.log`. It is **idempotent** — a second run detects that everything is in
place and installs nothing.

```bash
bash scripts/install_dev_tools.sh --check-only   # report only, never install
bash scripts/install_dev_tools.sh --strict       # exit code 1 if the env is not ready
```

### 3.2 Export the TorchScript model

```bash
python3 export_model.py            # -> model/model.pt
```

No local Python 3.13 with torch? Export inside a container instead:

```bash
docker run --rm -v "$(pwd)":/w -w /w python:3.13 \
    sh -c "pip install -r requirements.txt && python export_model.py"
```

```powershell
# PowerShell
docker run --rm -v "${PWD}:/w" -w /w python:3.13 `
    sh -c "pip install -r requirements.txt && python export_model.py"
```

### 3.3 Run inference locally

```bash
python3 app/inference.py example.jpg
```

### 3.4 Build both images

```bash
docker build -f Dockerfile.fat  -t ml-infer-fat:1.0  .
docker build -f Dockerfile.slim -t ml-infer-slim:1.0 .
```

### 3.5 Run inference in the containers

```bash
docker run --rm -v "$(pwd)/example.jpg:/app/example.jpg:ro" ml-infer-fat:1.0  example.jpg
docker run --rm -v "$(pwd)/example.jpg:/app/example.jpg:ro" ml-infer-slim:1.0 example.jpg
```

```powershell
# PowerShell
docker run --rm -v "${PWD}\example.jpg:/app/example.jpg:ro" ml-infer-fat:1.0  example.jpg
docker run --rm -v "${PWD}\example.jpg:/app/example.jpg:ro" ml-infer-slim:1.0 example.jpg
```

The fat image also carries `example.jpg` inside it, so `docker run --rm ml-infer-fat:1.0`
works without a mount. The slim image intentionally contains **only** the model and the
inference script, so the image has to be mounted in — that is part of the optimization.

### 3.6 Compare the images

```bash
docker images | grep ml-infer
docker history ml-infer-fat:1.0
docker history ml-infer-slim:1.0
```

### 3.7 Reproduce everything with one command

```bash
bash scripts/collect_metrics.sh              # uses the build cache
bash scripts/collect_metrics.sh --no-cache   # clean builds, honest build times
```

This exports the model (if needed), builds both images, runs inference in both,
diffs the predictions and writes every measurement to `metrics.txt`
(plus `output_fat.txt` / `output_slim.txt`). The numbers in `report.md` come from
this script.

---

## 4. Example output

```text
image : example.jpg
model : model/model.pt
top-3 predictions:
  1. class_id=<id>  confidence=<0.xxxx>  label=<class name>
  2. class_id=<id>  confidence=<0.xxxx>  label=<class name>
  3. class_id=<id>  confidence=<0.xxxx>  label=<class name>
```

```text
image : example.jpg
model : model/model.pt
top-3 predictions:
  1. class_id=258  confidence=0.2883  label=Samoyed
  2. class_id=259  confidence=0.0511  label=Pomeranian
  3. class_id=261  confidence=0.0176  label=keeshond
```

Both images produced the same classes and confidences on 2026-08-23. See
[`report.md`](report.md) and the raw [`metrics.txt`](metrics.txt).

---

## 5. Implementation notes

* **Modern weights API.** `export_model.py` uses
  `mobilenet_v2(weights=MobileNet_V2_Weights.DEFAULT)`, not the deprecated
  `pretrained=True`.
* **`model.eval()` before tracing.** Tracing a model in training mode would bake
  dropout and batch-norm batch statistics into the graph and produce unstable
  predictions.
* **`torch.jit.trace` + `torch.jit.freeze`.** Freezing inlines the parameters and
  removes training-only attributes, which makes the archive smaller and slightly faster.
* **Preprocessing comes from the weights.** `inference.py` uses
  `MobileNet_V2_Weights.DEFAULT.transforms()`, so resize/crop/normalize match
  exactly what the model was trained with. Class names come from
  `weights.meta["categories"]` — metadata only, nothing is downloaded at runtime.
* **No gradients.** Inference runs inside `torch.inference_mode()`.
* **Deterministic output.** `torch.set_num_threads(1)` keeps the results
  bit-identical between the two images.
* **CPU-only wheels.** `requirements.txt` pins `+cpu` builds from the PyTorch index.
  The default PyPI wheels drag in ~6 GB of NVIDIA CUDA packages that an inference-only
  container never uses. On macOS/arm64 drop the `+cpu` suffix.
* TorchScript is used here as the teaching format from the lecture. Production
  pipelines may instead use `torch.export`, ONNX or a dedicated inference runtime.

---

## 6. Fat vs slim in one paragraph

`Dockerfile.fat` is a single-stage build on the full `python:3.13` base: it installs a
complete build toolchain (`build-essential`, `gcc`, `cmake`, `git`, `vim`, …), keeps the
pip wheel cache and copies the **entire** build context into the image, including
`export_model.py`, `scripts/` and `requirements.txt` — none of which inference needs.
`Dockerfile.slim` is a multi-stage build on `python:3.13-slim`: the builder stage compiles
and installs the dependencies into `/install`, and the runtime stage copies only that tree
plus `app/` and `model/`, adds the single required system library (`libgomp1`), strips
bundled tests/headers/static libraries and runs as an unprivileged user. Same behaviour,
much less surface. Measured numbers are in [`report.md`](report.md).

---

## 7. Sample image

`example.jpg` is the sample dog photo from the official PyTorch Hub examples
repository — <https://github.com/pytorch/hub/blob/master/images/dog.jpg>
(BSD-3-Clause), downscaled to 640 px on the long side to keep the repository small.

---

## 8. Git workflow

```bash
git checkout -b lesson-3
git add .
git commit -m "Add lesson-3: TorchScript model, Dockerfiles, report"
git push --set-upstream origin lesson-3
```

Archive for the LMS submission:

```bash
zip -r ДЗ3_Кратцер_Вікторія.zip lesson-3/
unzip -l ДЗ3_Кратцер_Вікторія.zip
```
