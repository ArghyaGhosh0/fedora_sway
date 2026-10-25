#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
MINICONDA_DIR="${HOME}/miniconda3"
CONDA_BIN="${MINICONDA_DIR}/bin/conda"
ENV_NAME="p312"
PYTHON_VER="3.12"
LAUNCHER="${HOME}/.local/bin/run-jupyter"

log_info() { echo -e "\033[1;34m[*] $1\033[0m"; }
log_warn() { echo -e "\033[1;33m[!] $1\033[0m"; }
log_err()  { echo -e "\033[1;31m[✗] $1\033[0m" >&2; }
log_pass() { echo -e "\033[1;32m[✓] $1\033[0m"; }

# -----------------------------------------------------------------------------
# 1. Verify / Install Base Miniconda
# -----------------------------------------------------------------------------
if [[ ! -x "${CONDA_BIN}" ]]; then
    log_info "Miniconda binary not found at ${CONDA_BIN}. Downloading & installing..."
    INSTALLER="/tmp/Miniconda3-latest-Linux-x86_64.sh"
    curl -# -L "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" -o "${INSTALLER}"
    bash "${INSTALLER}" -b -p "${MINICONDA_DIR}"
    rm -f "${INSTALLER}"
    log_pass "Miniconda installed successfully."
else
    log_pass "Found existing Miniconda installation at ${MINICONDA_DIR}"
fi

# -----------------------------------------------------------------------------
# 2. Source Conda runtime functions directly
# -----------------------------------------------------------------------------
if [[ -f "${MINICONDA_DIR}/etc/profile.d/conda.sh" ]]; then
    # shellcheck disable=SC1091
    source "${MINICONDA_DIR}/etc/profile.d/conda.sh"
else
    log_err "Missing conda profile helper: ${MINICONDA_DIR}/etc/profile.d/conda.sh"
    exit 1
fi

# -----------------------------------------------------------------------------
# 3. Build / Rebuild Python 3.12 Environment with Jupyter
# -----------------------------------------------------------------------------
TARGET_ENV_DIR="${MINICONDA_DIR}/envs/${ENV_NAME}"

if [[ -d "${TARGET_ENV_DIR}" && -x "${TARGET_ENV_DIR}/bin/python" ]]; then
    log_info "Checking Python version inside existing '${ENV_NAME}'..."
    CURRENT_PY_VER="$("${TARGET_ENV_DIR}/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    if [[ "${CURRENT_PY_VER}" != "${PYTHON_VER}" ]]; then
        log_warn "Existing '${ENV_NAME}' has Python ${CURRENT_PY_VER}, expected ${PYTHON_VER}. Re-creating environment..."
        "${CONDA_BIN}" env remove -y -n "${ENV_NAME}"
    fi
fi

if [[ ! -d "${TARGET_ENV_DIR}" ]]; then
    log_info "Creating conda environment '${ENV_NAME}' with Python ${PYTHON_VER} and Jupyter packages..."
    "${CONDA_BIN}" create -y -n "${ENV_NAME}" -c conda-forge \
        "python=${PYTHON_VER}" \
        jupyterlab \
        notebook \
        ipykernel
    log_pass "Environment '${ENV_NAME}' created."
else
    log_info "Environment '${ENV_NAME}' exists. Ensuring Jupyter packages are installed..."
    "${CONDA_BIN}" install -y -n "${ENV_NAME}" -c conda-forge \
        jupyterlab \
        notebook \
        ipykernel
    log_pass "Dependencies confirmed."
fi

# -----------------------------------------------------------------------------
# 4. Register Kernel
# -----------------------------------------------------------------------------
log_info "Registering Jupyter kernel for Python ${PYTHON_VER}..."
"${TARGET_ENV_DIR}/bin/python" -m ipykernel install \
    --user \
    --name "${ENV_NAME}" \
    --display-name "Python 3.12 (${ENV_NAME})"

# -----------------------------------------------------------------------------
# 5. Wayland/Sway Headless Settings
# -----------------------------------------------------------------------------
mkdir -p "${HOME}/.jupyter"
JUPYTER_CONF="${HOME}/.jupyter/jupyter_notebook_config.py"
touch "${JUPYTER_CONF}"
if ! grep -q "c.ServerApp.open_browser" "${JUPYTER_CONF}"; then
    echo "c.ServerApp.open_browser = False" >> "${JUPYTER_CONF}"
fi

# -----------------------------------------------------------------------------
# 6. Generate Robust Launcher
# -----------------------------------------------------------------------------
mkdir -p "${HOME}/.local/bin"

cat << 'EOF' > "${LAUNCHER}"
#!/usr/bin/env bash
MINICONDA_DIR="${HOME}/miniconda3"
ENV_NAME="p312"

if [[ -f "${MINICONDA_DIR}/etc/profile.d/conda.sh" ]]; then
    source "${MINICONDA_DIR}/etc/profile.d/conda.sh"
    conda activate "${ENV_NAME}"
    exec jupyter lab "$@"
else
    echo "Error: Miniconda environment not found at ${MINICONDA_DIR}" >&2
    exit 1
fi
EOF

chmod +x "${LAUNCHER}"
log_pass "Launcher script created at ${LAUNCHER}"

# -----------------------------------------------------------------------------
# 7. Shell PATH Configuration
# -----------------------------------------------------------------------------
"${CONDA_BIN}" init bash >/dev/null 2>&1 || true

if ! grep -q 'HOME/.local/bin' "${HOME}/.bashrc"; then
    echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> "${HOME}/.bashrc"
    log_pass "Added ~/.local/bin to ~/.bashrc"
fi

echo "=========================================="
log_pass "Repair complete!"
echo "Run this command right now in your terminal:"
echo "    source ~/.bashrc && run-jupyter"
echo "=========================================="
