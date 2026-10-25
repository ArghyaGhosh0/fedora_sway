#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
MINICONDA_DIR="${HOME}/miniconda3"
CONDA_BIN="${MINICONDA_DIR}/bin/conda"
INSTALLER_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
TEMP_DIR="${TMPDIR:-/tmp}"
INSTALLER="${TEMP_DIR}/Miniconda3-latest-Linux-x86_64.sh"

ENV_NAME="p312"
PYTHON_VERSION="3.12"
LAUNCHER="${HOME}/.local/bin/run-jupyter"

# 4 GB required for Miniconda + Python 3.12 env + Jupyter packages + wheels
REQUIRED_HOME_SPACE_MB=4096
REQUIRED_TMP_SPACE_MB=500

# -----------------------------------------------------------------------------
# UI Helpers
# -----------------------------------------------------------------------------
log_info() { echo -e "\033[1;34m[*] $1\033[0m"; }
log_warn() { echo -e "\033[1;33m[!] $1\033[0m"; }
log_err()  { echo -e "\033[1;31m[✗] $1\033[0m" >&2; }
log_pass() { echo -e "\033[1;32m[✓] $1\033[0m"; }

# -----------------------------------------------------------------------------
# Cleanup trap
# -----------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 && -f "${INSTALLER}" ]]; then
        log_warn "Process interrupted or failed. Cleaning up temporary installer..."
        rm -f "${INSTALLER}"
    fi
}
trap cleanup EXIT INT TERM

# -----------------------------------------------------------------------------
# Pre-flight Checks
# -----------------------------------------------------------------------------
run_prechecks() {
    log_info "Running system pre-flight checks..."
    local failed=0

    # 1. Non-root execution check
    if [[ "${EUID}" -eq 0 ]]; then
        log_err "Do not run this script as root/sudo. Run as your regular user."
        failed=1
    else
        log_pass "User check: Running as non-root (${USER})"
    fi

    # 2. Architecture Check
    local arch
    arch="$(uname -m)"
    if [[ "${arch}" != "x86_64" ]]; then
        log_err "Incompatible architecture: ${arch}. Expected x86_64."
        failed=1
    else
        log_pass "Architecture check: x86_64 supported"
    fi

    # 3. Target directory check (allow directory if Miniconda is already installed)
    if [[ -d "${MINICONDA_DIR}" ]]; then
        log_pass "Miniconda directory exists at: ${MINICONDA_DIR} (will verify installation)"
    elif [[ -e "${MINICONDA_DIR}" ]]; then
        log_err "A file exists at target path: ${MINICONDA_DIR}"
        failed=1
    else
        log_pass "Path check: ${MINICONDA_DIR} is clear"
    fi

    # 4. Active Conda session check
    if [[ -n "${CONDA_DEFAULT_ENV:-}" || -n "${CONDA_PREFIX:-}" ]]; then
        log_err "An active Conda session is detected (${CONDA_DEFAULT_ENV:-unknown})."
        log_warn "Run 'conda deactivate' before proceeding."
        failed=1
    else
        log_pass "Environment check: No active Conda process"
    fi

    # 5. Core dependencies check
    local deps=("curl" "bash" "tar" "bzip2")
    for cmd in "${deps[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            log_err "Missing required dependency: ${cmd}"
            failed=1
        fi
    done
    [[ "${failed}" -eq 0 ]] && log_pass "Dependencies check: All tools available (${deps[*]})"

    # 6. Disk space check
    local home_avail tmp_avail
    home_avail=$(df -m "${HOME}" | awk 'NR==2 {print $4}')
    tmp_avail=$(df -m "${TEMP_DIR}" | awk 'NR==2 {print $4}')

    if [[ "${home_avail}" -lt "${REQUIRED_HOME_SPACE_MB}" ]]; then
        log_err "Insufficient disk space in ${HOME}. Required: ${REQUIRED_HOME_SPACE_MB} MB (~4 GB), Available: ${home_avail} MB"
        failed=1
    else
        log_pass "Disk check (${HOME}): ${home_avail} MB available"
    fi

    if [[ "${tmp_avail}" -lt "${REQUIRED_TMP_SPACE_MB}" ]]; then
        log_err "Insufficient temporary space in ${TEMP_DIR}. Required: ${REQUIRED_TMP_SPACE_MB} MB, Available: ${tmp_avail} MB"
        failed=1
    else
        log_pass "Disk check (${TEMP_DIR}): ${tmp_avail} MB available"
    fi

    # 7. Network connectivity check
    log_info "Verifying network connectivity to conda repositories..."
    if ! curl -s --head --request GET "https://repo.anaconda.com" | grep -qE "HTTP/[123.]+ (200|301|302)"; then
        log_err "Cannot reach repo.anaconda.com. Check your network connection."
        failed=1
    else
        log_pass "Network check: repo.anaconda.com reachable"
    fi

    # 8. Check write permissions
    if [[ ! -w "${HOME}" ]]; then
        log_err "Cannot write to ${HOME}."
        failed=1
    fi
    if [[ ! -w "${TEMP_DIR}" ]]; then
        log_err "Cannot write to temporary directory ${TEMP_DIR}."
        failed=1
    fi

    if [[ "${failed}" -ne 0 ]]; then
        echo "------------------------------------------"
        log_err "Pre-flight checks failed. Aborting installation."
        exit 1
    fi

    log_pass "All pre-flight checks passed."
}

# -----------------------------------------------------------------------------
# Miniconda Installation & Initialization
# -----------------------------------------------------------------------------
install_miniconda() {
    if [[ -x "${CONDA_BIN}" ]]; then
        log_pass "Miniconda already installed at ${MINICONDA_DIR}"
        return 0
    fi

    echo "------------------------------------------"
    log_info "Downloading Miniconda installer (~140 MB)..."
    curl -# -L "${INSTALLER_URL}" -o "${INSTALLER}"

    if [[ ! -s "${INSTALLER}" ]] || ! head -n 1 "${INSTALLER}" | grep -q "sh"; then
        log_err "Downloaded installer is corrupted or invalid."
        rm -f "${INSTALLER}"
        exit 1
    fi

    log_info "Installing Miniconda3 (-b)..."
    bash "${INSTALLER}" -b -p "${MINICONDA_DIR}"
    rm -f "${INSTALLER}"
    log_pass "Miniconda3 base installation finished."

    log_info "Initializing Conda for Bash..."
    "${CONDA_BIN}" init bash >/dev/null 2>&1 || true

    log_info "Disabling auto-activation of base environment..."
    "${CONDA_BIN}" config --set auto_activate_base false
}

# -----------------------------------------------------------------------------
# Configure Channels & Accept Terms of Service
# -----------------------------------------------------------------------------
configure_conda_channels() {
    echo "------------------------------------------"
    log_info "Configuring Conda channels & accepting Terms of Service..."

    # Automatically accept ToS if the subcommand exists in current conda version
    "${CONDA_BIN}" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main 2>/dev/null || true
    "${CONDA_BIN}" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r 2>/dev/null || true

    # Prioritize conda-forge to ensure compatibility and avoid license roadblocks
    "${CONDA_BIN}" config --add channels conda-forge
    "${CONDA_BIN}" config --set channel_priority strict

    log_pass "Conda channels configured (conda-forge priority set)."
}

# -----------------------------------------------------------------------------
# Setup Python 3.12 Environment & Jupyter
# -----------------------------------------------------------------------------
setup_jupyter_env() {
    echo "------------------------------------------"
    local target_env_dir="${MINICONDA_DIR}/envs/${ENV_NAME}"

    # Load conda shell functions for this subshell
    # shellcheck disable=SC1091
    source "${MINICONDA_DIR}/etc/profile.d/conda.sh"

    # Verify if environment exists and uses the exact required python version
    if [[ -d "${target_env_dir}" && -x "${target_env_dir}/bin/python" ]]; then
        local current_py
        current_py="$("${target_env_dir}/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
        if [[ "${current_py}" != "${PYTHON_VERSION}" ]]; then
            log_warn "Existing environment '${ENV_NAME}' has Python ${current_py}, expected ${PYTHON_VERSION}."
            log_info "Recreating environment '${ENV_NAME}'..."
            "${CONDA_BIN}" env remove -y -n "${ENV_NAME}"
        fi
    fi

    if [[ ! -d "${target_env_dir}" ]]; then
        log_info "Creating conda environment '${ENV_NAME}' with Python ${PYTHON_VERSION} and JupyterLab..."
        "${CONDA_BIN}" create -y -n "${ENV_NAME}" -c conda-forge \
            "python=${PYTHON_VERSION}" \
            jupyterlab \
            notebook \
            ipykernel
        log_pass "Environment '${ENV_NAME}' created."
    else
        log_info "Environment '${ENV_NAME}' exists. Verifying packages..."
        "${CONDA_BIN}" install -y -n "${ENV_NAME}" -c conda-forge \
            jupyterlab \
            notebook \
            ipykernel
        log_pass "Packages verified."
    fi

    # Register kernel for Jupyter UI
    log_info "Registering Jupyter kernel for Python ${PYTHON_VERSION}..."
    "${target_env_dir}/bin/python" -m ipykernel install \
        --user \
        --name "${ENV_NAME}" \
        --display-name "Python 3.12 (${ENV_NAME})"
    log_pass "Kernel registered as: Python 3.12 (${ENV_NAME})"

    # Configure Sway/Wayland headless settings (prevent browser open failures)
    log_info "Configuring headless settings for Sway..."
    local jupyter_config_dir="${HOME}/.jupyter"
    mkdir -p "${jupyter_config_dir}"
    local jupyter_conf="${jupyter_config_dir}/jupyter_notebook_config.py"
    touch "${jupyter_conf}"
    if ! grep -q "c.ServerApp.open_browser" "${jupyter_conf}"; then
        echo "c.ServerApp.open_browser = False" >> "${jupyter_conf}"
    fi

    # Write run-jupyter launcher
    mkdir -p "${HOME}/.local/bin"
    cat << 'EOF' > "${LAUNCHER}"
#!/usr/bin/env bash
MINICONDA_DIR="${HOME}/miniconda3"
ENV_NAME="p312"

if [[ -f "${MINICONDA_DIR}/etc/profile.d/conda.sh" ]]; then
    # shellcheck disable=SC1091
    source "${MINICONDA_DIR}/etc/profile.d/conda.sh"
    conda activate "${ENV_NAME}"
    exec jupyter lab "$@"
else
    echo "Error: Conda profile script not found at ${MINICONDA_DIR}/etc/profile.d/conda.sh" >&2
    exit 1
fi
EOF
    chmod +x "${LAUNCHER}"
    log_pass "Created executable launcher: ${LAUNCHER}"

    # Ensure ~/.local/bin is in PATH inside ~/.bashrc
    if ! grep -q 'HOME/.local/bin' "${HOME}/.bashrc"; then
        echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> "${HOME}/.bashrc"
        log_pass "Added ~/.local/bin to ~/.bashrc"
    fi
}

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------
echo "=========================================="
echo " Miniconda + Python 3.12 + Jupyter Setup"
echo " Target path: ${MINICONDA_DIR}"
echo " Target env : ${ENV_NAME} (Python ${PYTHON_VERSION})"
echo "=========================================="

run_prechecks
install_miniconda
configure_conda_channels
setup_jupyter_env

echo "=========================================="
log_pass "Setup completed successfully."
echo ""
echo "To start using Jupyter immediately:"
echo "    source ~/.bashrc"
echo "    run-jupyter"
echo "=========================================="
