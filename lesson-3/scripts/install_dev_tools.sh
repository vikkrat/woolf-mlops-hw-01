#!/usr/bin/env bash
#
# install_dev_tools.sh - check and prepare the local MLOps dev environment.
#
# Verifies (and, where possible, installs) everything the project needs:
#   * Docker Engine
#   * Docker Compose V2  (docker compose version)
#   * Python >= 3.13 and pip
#   * Python packages: torch, torchvision, pillow (from requirements.txt)
#
# The script is IDEMPOTENT: running it twice changes nothing on an already
# prepared machine - every step is guarded by a "is it already there?" check.
# Everything it prints is also appended to install.log in the project root.
#
# Usage:
#   ./scripts/install_dev_tools.sh              # check, install missing Python deps
#   ./scripts/install_dev_tools.sh --check-only # only report, never install
#   ./scripts/install_dev_tools.sh --strict     # exit 1 if the env is not ready
#
set -uo pipefail

# ---------------------------------------------------------------------------
# Paths & configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_FILE="${PROJECT_ROOT}/install.log"
REQUIREMENTS_FILE="${PROJECT_ROOT}/requirements.txt"

REQUIRED_PY_MAJOR=3
REQUIRED_PY_MINOR=13
PY_PACKAGES=(torch torchvision pillow)

CHECK_ONLY=0
STRICT=0
MISSING=0

for arg in "$@"; do
    case "${arg}" in
        --check-only) CHECK_ONLY=1 ;;
        --strict)     STRICT=1 ;;
        -h|--help)
            sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: ${arg} (use --help)" >&2
            exit 2
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Logging helpers - every message goes to stdout AND to install.log
# ---------------------------------------------------------------------------
log() {
    local level="$1"; shift
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S') [${level}] $*"
    echo "${line}" | tee -a "${LOG_FILE}"
}

ok()      { log "OK     " "$@"; }
info()    { log "INFO   " "$@"; }
warn()    { log "WARN   " "$@"; }
missing() { log "MISSING" "$@"; MISSING=$((MISSING + 1)); }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Package-manager detection (only used when something has to be installed)
# ---------------------------------------------------------------------------
detect_pkg_manager() {
    if   has_cmd apt-get; then echo "apt-get"
    elif has_cmd dnf;     then echo "dnf"
    elif has_cmd yum;     then echo "yum"
    elif has_cmd pacman;  then echo "pacman"
    elif has_cmd brew;    then echo "brew"
    else echo "unknown"
    fi
}

: > /dev/null  # no-op, keeps shellcheck happy about the block above

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
touch "${LOG_FILE}"
{
    echo ""
    echo "==========================================================="
} >> "${LOG_FILE}"
info "install_dev_tools.sh started (project root: ${PROJECT_ROOT})"
info "host: $(uname -srm 2>/dev/null || echo 'unknown') | user: $(id -un 2>/dev/null || echo 'unknown')"
[[ ${CHECK_ONLY} -eq 1 ]] && info "mode: --check-only (nothing will be installed)"

PKG_MANAGER="$(detect_pkg_manager)"
info "detected package manager: ${PKG_MANAGER}"

# ---------------------------------------------------------------------------
# 1. Docker Engine
# ---------------------------------------------------------------------------
check_docker() {
    if has_cmd docker; then
        ok "docker found: $(docker --version 2>&1 | head -n1)"
        if docker info >/dev/null 2>&1; then
            ok "docker daemon is running"
        else
            warn "docker is installed but the daemon is not reachable - start Docker Desktop / 'sudo systemctl start docker'"
        fi
    else
        missing "docker is NOT installed"
        info "  install it with the official script:  curl -fsSL https://get.docker.com | sh"
        info "  docs: https://docs.docker.com/engine/install/"
    fi
}

# ---------------------------------------------------------------------------
# 2. Docker Compose V2 (the plugin, i.e. 'docker compose', not 'docker-compose')
# ---------------------------------------------------------------------------
check_docker_compose() {
    if ! has_cmd docker; then
        missing "docker compose V2 cannot be checked - docker is absent"
        return
    fi
    if docker compose version >/dev/null 2>&1; then
        ok "docker compose V2 found: $(docker compose version 2>&1 | head -n1)"
    else
        missing "docker compose V2 (plugin) is NOT available"
        if has_cmd docker-compose; then
            warn "  legacy 'docker-compose' V1 detected - the project requires V2 ('docker compose')"
        fi
        info "  install the plugin: https://docs.docker.com/compose/install/linux/"
        info "  e.g. Debian/Ubuntu:  sudo apt-get install -y docker-compose-plugin"
    fi
}

# ---------------------------------------------------------------------------
# 3. Python >= 3.13
# ---------------------------------------------------------------------------
PYTHON_BIN=""

check_python() {
    # Важливо: у Windows Git Bash команда `python3` іноді вказує на порожній
    # Microsoft Store alias. Тому перевіряємо не лише наявність команди, а й те,
    # що інтерпретатор справді запускається та повертає версію.
    local candidate
    for candidate in python3.13 python3 python; do
        if has_cmd "${candidate}" && \
           "${candidate}" -c 'import sys; print(sys.version_info.major)' >/dev/null 2>&1; then
            PYTHON_BIN="$(command -v "${candidate}")"
            break
        fi
    done

    if [[ -z "${PYTHON_BIN}" ]]; then
        missing "python3 is NOT installed"
        info "  install Python ${REQUIRED_PY_MAJOR}.${REQUIRED_PY_MINOR}+ : https://www.python.org/downloads/"
        return
    fi

    local version major minor
    version="$("${PYTHON_BIN}" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])')"
    major="${version%%.*}"
    minor="$(echo "${version}" | cut -d. -f2)"

    if [[ "${major}" -gt ${REQUIRED_PY_MAJOR} ]] || \
       { [[ "${major}" -eq ${REQUIRED_PY_MAJOR} ]] && [[ "${minor}" -ge ${REQUIRED_PY_MINOR} ]]; }; then
        ok "python found: ${PYTHON_BIN} (${version}) >= ${REQUIRED_PY_MAJOR}.${REQUIRED_PY_MINOR}"
    else
        missing "python ${version} is older than the required ${REQUIRED_PY_MAJOR}.${REQUIRED_PY_MINOR}"
        info "  the Docker images pin python:3.13 - please install Python 3.13 locally as well"
        case "${PKG_MANAGER}" in
            apt-get) info "  e.g.  sudo apt-get install -y python3.13 python3.13-venv" ;;
            brew)    info "  e.g.  brew install python@3.13" ;;
            dnf|yum) info "  e.g.  sudo ${PKG_MANAGER} install -y python3.13" ;;
        esac
    fi
}

# ---------------------------------------------------------------------------
# 4. pip
# ---------------------------------------------------------------------------
PIP_CMD=()

check_pip() {
    if [[ -z "${PYTHON_BIN}" ]]; then
        missing "pip cannot be checked - python is absent"
        return
    fi
    if "${PYTHON_BIN}" -m pip --version >/dev/null 2>&1; then
        PIP_CMD=("${PYTHON_BIN}" -m pip)
        ok "pip found: $("${PYTHON_BIN}" -m pip --version 2>&1 | head -n1)"
    elif has_cmd pip3; then
        PIP_CMD=(pip3)
        ok "pip found: $(pip3 --version 2>&1 | head -n1)"
    else
        missing "pip is NOT installed"
        info "  install it with:  ${PYTHON_BIN} -m ensurepip --upgrade"
    fi
}

# ---------------------------------------------------------------------------
# 5. Python ML packages (torch / torchvision / pillow)
# ---------------------------------------------------------------------------
python_package_version() {
    # Prints the installed version or nothing if the package is absent.
    "${PYTHON_BIN}" - "$1" <<'PY' 2>/dev/null
import importlib.metadata as md
import sys
try:
    print(md.version(sys.argv[1]))
except Exception:
    sys.exit(1)
PY
}

install_requirements() {
    if [[ ${CHECK_ONLY} -eq 1 ]]; then
        info "  --check-only: skipping 'pip install -r requirements.txt'"
        return
    fi
    if [[ ${#PIP_CMD[@]} -eq 0 ]]; then
        warn "  cannot install Python packages - pip is unavailable"
        return
    fi
    if [[ ! -f "${REQUIREMENTS_FILE}" ]]; then
        warn "  ${REQUIREMENTS_FILE} not found - nothing to install"
        return
    fi

    info "  installing from ${REQUIREMENTS_FILE} ..."
    # --break-system-packages is needed on PEP 668 ("externally managed") distros
    # and is silently ignored by older pip versions that do not know the flag.
    local pip_args=(install --disable-pip-version-check -r "${REQUIREMENTS_FILE}")
    if "${PIP_CMD[@]}" install --help 2>/dev/null | grep -q -- "--break-system-packages"; then
        pip_args+=(--break-system-packages)
    fi

    if "${PIP_CMD[@]}" "${pip_args[@]}" >>"${LOG_FILE}" 2>&1; then
        ok "  pip install finished (full output in install.log)"
    else
        warn "  pip install failed - see install.log for details"
        warn "  hint: on macOS/arm64 remove the '+cpu' suffixes from requirements.txt"
    fi
}

check_python_packages() {
    if [[ -z "${PYTHON_BIN}" ]]; then
        missing "python packages cannot be checked - python is absent"
        return
    fi

    local pkg version need_install=0
    for pkg in "${PY_PACKAGES[@]}"; do
        version="$(python_package_version "${pkg}")"
        if [[ -n "${version}" ]]; then
            ok "python package '${pkg}' is installed (${version})"
        else
            warn "python package '${pkg}' is NOT installed"
            need_install=1
        fi
    done

    if [[ ${need_install} -eq 1 ]]; then
        install_requirements
        # Re-check after the install attempt - this is what makes the run idempotent:
        # a second execution finds everything in place and installs nothing.
        for pkg in "${PY_PACKAGES[@]}"; do
            version="$(python_package_version "${pkg}")"
            if [[ -n "${version}" ]]; then
                ok "python package '${pkg}' is now installed (${version})"
            else
                missing "python package '${pkg}' is still not available"
            fi
        done
    else
        info "all Python packages already present - nothing to install (idempotent run)"
    fi
}

# ---------------------------------------------------------------------------
# 6. Final smoke test
# ---------------------------------------------------------------------------
smoke_test() {
    [[ -z "${PYTHON_BIN}" ]] && return
    local out
    out="$("${PYTHON_BIN}" -c 'import torch, torchvision, PIL; print(f"torch={torch.__version__} torchvision={torchvision.__version__} pillow={PIL.__version__}")' 2>&1)"
    if [[ $? -eq 0 ]]; then
        ok "smoke test: ${out}"
    else
        warn "smoke test failed: ${out}"
    fi
}

# ---------------------------------------------------------------------------
# Run all checks
# ---------------------------------------------------------------------------
check_docker
check_docker_compose
check_python
check_pip
check_python_packages
smoke_test

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
info "-----------------------------------------------------------"
if [[ ${MISSING} -eq 0 ]]; then
    ok "ENVIRONMENT READY - all required tools and packages are available"
    info "log written to ${LOG_FILE}"
    exit 0
fi

warn "ENVIRONMENT NOT READY - ${MISSING} item(s) missing (see the MISSING lines above)"
info "log written to ${LOG_FILE}"
if [[ ${STRICT} -eq 1 ]]; then
    exit 1
fi
exit 0
