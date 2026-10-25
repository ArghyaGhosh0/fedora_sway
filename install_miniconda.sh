#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
MINICONDA_DIR="${HOME}/miniconda3"
INSTALLER_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
TEMP_DIR="${TMPDIR:-/tmp}"
INSTALLER="${TEMP_DIR}/Miniconda3-latest-Linux-x86_64.sh"

ENV_NAME="p312"
PYTHON_VERSION="3.12"

# 4 GB recommended for Miniconda + Python 3.12 env + Jupyter packages + wheels
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
# Comprehensive Pre-flight Checks
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

    # 3. Target directory & path collision check
    if [[ -d "${MINICONDA_DIR}" ]]; then
        log_warn "Target directory already exists: ${MINICONDA_DIR}"
        log_info "Will skip Miniconda base install and configure the Python ${PYTHON_VERSION} Jupyter env."
    elif [[ -e "${MINICONDA_DIR}" ]]; then
        log_err "A file exists at target path: ${MINICONDA_DIR}"
        failed=1
    else
        log_pass "Path check: ${MINICONDA_DIR} is clear"
    fi

    # 4. Check for an active conda session
    if [[ -n "${CONDA_DEFAULT_ENV:-}" || -n "${CONDA_PREFIX:-}" ]]; then
        log_err "An active Conda session is detected (${CONDA_DEFAULT_ENV:-unknown})."
        log_warn "Run 'conda deactivate' before installing."
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
    log_info "Verifying connection to repo.anaconda.com..."
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

    # Abort if any precheck failed
    if [[ "${failed}" -ne 0 ]]; then
        echo "------------------------------------------"
        log_err "Pre-flight checks failed. Aborting setup."
        exit 1
    fi

    log_pass "All pre-flight checks passed."
}

# -----------------------------------------------------------------------------
# Cleanup trap
# -----------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 && -f "${INSTALLER}" ]]; then
        log_warn "Installation failed or interrupted. Cleaning up installer..."
        rm -f "${INSTALLER}"
    fi
}
trap cleanup EXIT INT TERM

# -----------------------------------------------------------------------------
# Miniconda Base Installation
# -----------------------------------------------------------------------------
install_miniconda() {
    if [[ -d "${MINICONDA_DIR}" ]]; then
        log_info "Miniconda already present at ${MINICONDA_DIR}. Skipping bootstrap."
        return 0
    fi

    echo "------------------------------------------"
    log_info "Downloading Miniconda installer..."
    curl -# -L "${INSTALLER_URL}" -o "${INSTALLER}"

    if [[ ! -s "${INSTALLER}" ]] || ! head -n 1 "${INSTALLER}" | grep -q "sh"; then
        log_err "Downloaded file is corrupted or invalid."
        rm -f "${INSTALLER}"
        exit 1
    fi

    log_info "Installing Miniconda3 to ${MINICONDA_DIR}..."
    bash "${INSTALLER}" -b -p "${MINICONDA_DIR}"
    rm -f "${INSTALLER}"

    log_info "Initializing Conda for Bash..."
    "${MINICONDA_DIR}/bin/conda" init bash

    log_info "Disabling auto-activation of base environment..."
    "${MINICONDA_DIR}/bin/conda" config --set auto_activate_base false
}

# -----------------------------------------------------------------------------
# Setup Python 3.12 & Jupyter Environment
# -----------------------------------------------------------------------------
setup_jupyter_env() {
    local conda_bin="${MINICONDA_DIR}/bin/conda"

    echo "------------------------------------------"
    log_info "Configuring Conda environment '${ENV_NAME}' with Python ${PYTHON_VERSION}..."

    if "${conda_bin}" env list | grep -qE "^${ENV_NAME}\s"; then
        log_warn "Environment '${ENV_NAME}' already exists. Updating packages..."
        "${conda_bin}" install -y -n "${ENV_NAME}" -c conda-forge \
            "python=${PYTHON_VERSION}" jupyterlab notebook ipykernel nb_conda_kernels
    else
        "${conda_bin}" create -y -n "${ENV_NAME}" -c conda-forge \
            "python=${PYTHON_VERSION}" jupyterlab notebook ipykernel nb_conda_kernels
    fi

    log_info "Registering Python 3.12 ipykernel..."
    "${MINICONDA_DIR}/envs/${ENV_NAME}/bin/python" -m ipykernel install \
        --user \
        --name "${ENV_NAME}" \
        --display-name "Python 3.12 (${ENV_NAME})"

    # Sway / Wayland friendly default config
    log_info "Configuring Jupyter defaults..."
    local jupyter_config_dir="${HOME}/.jupyter"
    mkdir -p "${jupyter_config_dir}"

    local jupyter_conf="${jupyter_config_dir}/jupyter_notebook_config.py"
    touch "${jupyter_conf}"

    # Do not attempt to pop open browser windows automatically in tiling Wayland sessions
    if ! grep -q "c.ServerApp.open_browser" "${jupyter_conf}"; then
        echo "c.ServerApp.open_browser = False" >> "${jupyter_conf}"
    fi

    # Create a quick launcher binary in ~/.local/bin
    mkdir -p "${HOME}/.local/bin"
    cat << 'EOF' > "${HOME}/.local/bin/run-jupyter"
#!/usr/bin/env bash
source "${HOME}/miniconda3/etc/profile.d/conda.sh"
conda activate p312
exec jupyter lab "$@"
EOF
    chmod +x "${HOME}/.local/bin/run-jupyter"
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
echo "=========================================="
echo " Miniconda3 + Python 3.12 Jupyter Setup"
echo " Target path: ${MINICONDA_DIR}"
echo " Target Env : ${ENV_NAME} (Python ${PYTHON_VERSION})"
echo "=========================================="

run_prechecks
install_miniconda
setup_jupyter_env

echo "=========================================="
log_pass "Installation completed successfully."
echo ""
echo "Verify setup:"
echo "    source ~/.bashrc"
echo "    conda activate ${ENV_NAME}"
echo "    python --version   # (will report Python 3.12.x)"
echo ""
echo "Launch Jupyter:"
echo "    run-jupyter"
echo "    # or: conda activate ${ENV_NAME} && jupyter lab"
echo "=========================================="
