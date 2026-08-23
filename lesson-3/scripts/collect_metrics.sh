#!/usr/bin/env bash
#
# collect_metrics.sh - one command that reproduces the whole assignment
# and writes every measurement into metrics.txt.
#
# It will:
#   1. export model/model.pt (if missing)
#   2. build ml-infer-fat:1.0  and measure the build time
#   3. build ml-infer-slim:1.0 and measure the build time
#   4. run inference in both images on example.jpg and diff the results
#   5. collect image sizes, layer counts and the heaviest layers
#
# Usage:
#   bash scripts/collect_metrics.sh                # normal run (uses build cache)
#   bash scripts/collect_metrics.sh --no-cache     # clean builds (honest build times)
#
set -uo pipefail
export MSYS_NO_PATHCONV=1   # keep Git Bash from mangling container paths on Windows

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}" || exit 1

METRICS_FILE="${PROJECT_ROOT}/metrics.txt"
FAT_IMAGE="ml-infer-fat:1.0"
SLIM_IMAGE="ml-infer-slim:1.0"
FAT_OUT="${PROJECT_ROOT}/output_fat.txt"
SLIM_OUT="${PROJECT_ROOT}/output_slim.txt"
BUILD_ARGS=()

[[ "${1:-}" == "--no-cache" ]] && BUILD_ARGS+=(--no-cache)

# Docker Desktop on Windows needs a native path for bind mounts.
HOST_DIR="$(pwd)"
if command -v cygpath >/dev/null 2>&1; then
    HOST_DIR="$(cygpath -w "$(pwd)")"
fi

say()  { echo "$@" | tee -a "${METRICS_FILE}"; }
head2() { say ""; say "=== $* ==="; }

: > "${METRICS_FILE}"
say "metrics collected: $(date '+%Y-%m-%d %H:%M:%S')"
say "host: $(uname -srm 2>/dev/null || echo unknown)"

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: docker daemon is not reachable. Start Docker Desktop and retry." >&2
    exit 1
fi
say "docker: $(docker --version)"
say "compose: $(docker compose version 2>/dev/null | head -n1)"

# ---------------------------------------------------------------------------
# 1. TorchScript model
# ---------------------------------------------------------------------------
head2 "1. MODEL EXPORT"
if [[ -f model/model.pt ]]; then
    say "model/model.pt already exists - skipping export (idempotent)"
elif python3 -c "import torch, torchvision" >/dev/null 2>&1; then
    say "exporting with the local Python interpreter ..."
    python3 export_model.py 2>&1 | tee -a "${METRICS_FILE}"
else
    say "local torch not found - exporting inside a python:3.13 container ..."
    docker run --rm -v "${HOST_DIR}:/w" -w /w python:3.13 \
        sh -c "pip install --no-cache-dir -q -r requirements.txt && python export_model.py" \
        2>&1 | tee -a "${METRICS_FILE}"
fi
say "model file: $(ls -lh model/model.pt 2>/dev/null | awk '{print $5}')"

# ---------------------------------------------------------------------------
# 2-3. Builds
# ---------------------------------------------------------------------------
build_image() {
    local dockerfile="$1" tag="$2" start end
    head2 "BUILD ${tag} (-f ${dockerfile} ${BUILD_ARGS[*]:-})"
    start=$(date +%s)
    if docker build ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} -f "${dockerfile}" -t "${tag}" . >/dev/null 2>&1; then
        end=$(date +%s)
        say "build status : OK"
        say "build time   : $(( end - start )) s"
    else
        end=$(date +%s)
        say "build status : FAILED after $(( end - start )) s"
        say "re-run manually to see the error: docker build -f ${dockerfile} -t ${tag} ."
        return 1
    fi
}

build_image Dockerfile.fat  "${FAT_IMAGE}"
build_image Dockerfile.slim "${SLIM_IMAGE}"

# ---------------------------------------------------------------------------
# 4. Inference in both images
# ---------------------------------------------------------------------------
run_inference() {
    local tag="$1" outfile="$2" start end
    head2 "INFERENCE ${tag}"
    start=$(date +%s%N)
    docker run --rm -v "${HOST_DIR}/example.jpg:/app/example.jpg:ro" "${tag}" example.jpg \
        > "${outfile}" 2>&1
    end=$(date +%s%N)
    cat "${outfile}" | tee -a "${METRICS_FILE}"
    say "wall time    : $(( (end - start) / 1000000 )) ms"
}

run_inference "${FAT_IMAGE}"  "${FAT_OUT}"
run_inference "${SLIM_IMAGE}" "${SLIM_OUT}"

head2 "INFERENCE DIFF (fat vs slim)"
if diff <(grep -E 'class_id' "${FAT_OUT}") <(grep -E 'class_id' "${SLIM_OUT}") >/dev/null 2>&1; then
    say "IDENTICAL - top-3 predictions match bit for bit"
else
    say "DIFFERENT - see the diff below"
    diff "${FAT_OUT}" "${SLIM_OUT}" | tee -a "${METRICS_FILE}"
fi

# ---------------------------------------------------------------------------
# 5. Image comparison
# ---------------------------------------------------------------------------
head2 "5. IMAGE SIZES"
docker images | head -n1 | tee -a "${METRICS_FILE}"
docker images | grep ml-infer | tee -a "${METRICS_FILE}"

head2 "5.1 LAYER COUNT"
for tag in "${FAT_IMAGE}" "${SLIM_IMAGE}"; do
    say "${tag}: $(docker image inspect -f '{{len .RootFS.Layers}}' "${tag}" 2>/dev/null) layers (rootfs), \
$(docker history -q "${tag}" 2>/dev/null | wc -l | tr -d ' ') history entries"
done

head2 "5.2 DOCKER HISTORY - FAT"
docker history --no-trunc --format 'table {{.Size}}\t{{.CreatedBy}}' "${FAT_IMAGE}" \
    | cut -c1-160 | tee -a "${METRICS_FILE}"

head2 "5.3 DOCKER HISTORY - SLIM"
docker history --no-trunc --format 'table {{.Size}}\t{{.CreatedBy}}' "${SLIM_IMAGE}" \
    | cut -c1-160 | tee -a "${METRICS_FILE}"

head2 "5.4 BASE IMAGE SIZES"
docker images | grep -E '^python ' | tee -a "${METRICS_FILE}"

head2 "5.5 WHAT IS INSIDE EACH IMAGE (/app)"
say "--- fat /app:"
docker run --rm --entrypoint sh "${FAT_IMAGE}" -c "ls -la /app" 2>&1 | tee -a "${METRICS_FILE}"
say "--- slim /app:"
docker run --rm --entrypoint sh "${SLIM_IMAGE}" -c "ls -la /app" 2>&1 | tee -a "${METRICS_FILE}"
say "--- build tools present? (gcc / pip cache)"
say "fat  gcc : $(docker run --rm --entrypoint sh "${FAT_IMAGE}"  -c 'command -v gcc || echo absent' 2>&1)"
say "slim gcc : $(docker run --rm --entrypoint sh "${SLIM_IMAGE}" -c 'command -v gcc || echo absent' 2>&1)"

head2 "DONE"
say "all measurements saved to metrics.txt"
say "inference outputs saved to output_fat.txt / output_slim.txt"
