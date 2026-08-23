# Report — fat vs slim Docker image for TorchScript inference

**Project:** `lesson-3` — MobileNetV2 (TorchScript) image classification
**Images:** `ml-infer-fat:1.0` (`Dockerfile.fat`) and `ml-infer-slim:1.0` (`Dockerfile.slim`)
**Model:** MobileNetV2, ImageNet weights, exported with `torch.jit.trace` + `torch.jit.freeze`
**Input:** `example.jpg` (640 px, dog photo from the PyTorch Hub examples)

All numbers below were produced by `scripts/collect_metrics.ps1 -NoCache`
and are stored verbatim in `metrics.txt`.

---

## 1. Comparison table

| Metric | Fat image | Slim image |
|---|---|---|
| Base image | `python:3.13` | `python:3.13-slim` (multi-stage) |
| Image size | 2.62 GB | 792 MB |
| Layer count (`RootFS.Layers`) | 12 | 10 |
| Build time (`--no-cache`) | 71 s | 84 s |
| Inference result (top-3) | Samoyed / Pomeranian / keeshond | identical |
| Build toolchain in final image | present (`gcc`, `build-essential`, `cmake`, …) | absent |
| pip cache in final image | kept | removed (`--no-cache-dir`) |
| Files in `/app` | whole build context | only `app/` and `model/` |
| Runs as | `root` | unprivileged `appuser` (uid 10001) |

---

## 2. Environment

| | |
|---|---|
| Host OS | Windows 10.0.26200, Docker Desktop Linux containers (x86_64) |
| Docker version | 27.5.1 |
| Docker Compose | v2.32.4-desktop.1 |
| Python in images | 3.13 |
| torch / torchvision / pillow | 2.7.0+cpu / 0.22.0+cpu / 11.2.1 |

---

## 3. Inference results

### 3.1 Fat image

```text
1. class_id=258  confidence=0.2883  label=Samoyed
2. class_id=259  confidence=0.0511  label=Pomeranian
3. class_id=261  confidence=0.0176  label=keeshond
```

### 3.2 Slim image

```text
1. class_id=258  confidence=0.2883  label=Samoyed
2. class_id=259  confidence=0.0511  label=Pomeranian
3. class_id=261  confidence=0.0176  label=keeshond
```

### 3.3 Verdict

`IDENTICAL` — the top-3 predictions match bit for bit.

The two images run the *same* `app/inference.py` against the *same* frozen TorchScript
archive with the same pinned dependency versions and `torch.set_num_threads(1)`, so the
predictions are expected to match bit for bit. Optimizing the image changes what is
*shipped around* the model, never the model itself.

---

## 4. Heaviest layers

### 4.1 Fat image (`docker history ml-infer-fat:1.0`)

| Size | Layer |
|---|---|
| 1.11 GB | `pip install -r requirements.txt` (packages plus retained pip cache) |
| 656 MB | toolchain layer inherited from the full `python:3.13` base |
| 390 MB | explicitly installed build and diagnostic tools |

### 4.2 Slim image (`docker history ml-infer-slim:1.0`)

| Size | Layer |
|---|---|
| 645 MB | Python dependencies copied from `/install` |
| 78.6 MB | Debian layer from `python:3.13-slim` |
| 35.6 MB | CPython layer inherited from the slim base image |

---

## 5. Analysis — where the weight comes from

**a) Base image.** `python:3.13` is a full Debian userland with build tooling, docs and
locales. `python:3.13-slim` drops all of that and keeps only what CPython needs. This is
the single cheapest optimization available: change one word in `FROM`.

**b) Build toolchain kept at runtime.** The fat image installs `build-essential`, `gcc`,
`g++`, `make`, `cmake`, `git`, `curl`, `wget`, `vim`, `htop`, `unzip`. Compilers are needed
*while installing* packages that ship as source, never while running inference. In the slim
image they live in the builder stage only and never reach the final layer — the classic
multi-stage win.

**c) pip cache.** Without `--no-cache-dir`, pip keeps every downloaded wheel under
`~/.cache/pip`. For the torch stack that is hundreds of megabytes of dead weight, and it
sits in the same layer as the install, so it cannot be deleted later without rebuilding.

**d) Build context.** `Dockerfile.fat` does `COPY . .`, so `export_model.py`, `scripts/`,
`requirements.txt` and `example.jpg` all end up in the runtime image. `Dockerfile.slim`
copies only `app/` and `model/`. `.dockerignore` additionally keeps `.git`, `__pycache__`,
`*.pyc`, virtualenvs, caches, logs and archives out of the context for *both* builds —
which also speeds the build up, because the daemon transfers less data.

**e) CPU-only wheels.** `requirements.txt` pins `torch==2.7.0+cpu` from the PyTorch index.
The default PyPI wheel pulls ~6 GB of `nvidia-*` CUDA packages that a CPU inference
container can never use. This one line is the largest single saving in the whole project
and it applies to *both* images.

**f) Stripped artefacts.** The slim builder removes bundled tests, `include/` headers,
`*.a` static libraries and `__pycache__` from the installed torch tree — files that only
matter when *compiling against* torch.

**g) Security bonus.** The slim runtime has no compiler, no `curl`/`wget`, no `git` and
runs as a non-root user, so it is a smaller attack surface, not just a smaller download.

---

## 6. Further optimization ideas

1. **Distroless / Alpine-style runtime.** Copy the packages into
   `gcr.io/distroless/python3` — no shell, no package manager. Adds friction to debugging.
2. **Export to ONNX + ONNX Runtime.** Drops the ~500 MB `libtorch_cpu.so` entirely; an
   ORT-based image typically lands in the low hundreds of MB.
3. **Quantization (INT8) or `torch.export`.** Smaller model file and faster CPU inference.
4. **Wheel pre-download stage + BuildKit cache mounts**
   (`RUN --mount=type=cache,target=/root/.cache/pip`) — keeps rebuilds fast without
   putting the cache into a layer.
5. **Serve instead of one-shot runs.** Wrapping the model in FastAPI amortizes the
   ~1-2 s model load across requests instead of paying it per `docker run`.
6. **`.dockerignore` discipline + layer ordering.** Copy `requirements.txt` and install
   dependencies *before* copying source, so code edits never invalidate the dependency layer
   (already done in both Dockerfiles).

---

## 7. Conclusion

The fat image contains substantial runtime ballast: the full base OS, compilers,
diagnostic utilities, pip cache and project files that inference does not use. The
multi-stage build reduced the image from 2.62 GB to 792 MB (about 70%) and from 12 to
10 filesystem layers while removing the compiler and running as a non-root user. Both
images returned exactly the same top-3 predictions, so the optimization preserved model
behaviour. The next largest size reduction would likely come from replacing the PyTorch
runtime with an ONNX Runtime deployment and then evaluating quantization.
