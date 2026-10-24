#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
MINICONDA_DIR="${HOME}/miniconda3"
INSTALLER_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
TEMP_DIR="${TMPDIR:-/tmp}"
INSTALLER="${TEMP_DIR}/Miniconda3-latest-Linux-x86_64.sh"

REQUIRED_HOME_SPACE_MB=2048  # 2 GB (Miniconda needs ~500 MB to 1 GB)
REQUIRED_TMP_SPACE_MB=300    # 300 MB

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
        log_err "Target directory already exists: ${MINICONDA_DIR}"
        log_warn "Remove or rename the existing directory before running."
        failed=1
    elif [[ -e "${MINICONDA_DIR}" ]]; then
        log_err "A file already exists at target path: ${MINICONDA_DIR}"
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
        log_err "Insufficient disk space in ${HOME}. Required: ${REQUIRED_HOME_SPACE_MB} MB (~2 GB), Available: ${home_avail} MB"
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
        log_err "Pre-flight checks failed. Aborting installation."
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
# Main Execution
# -----------------------------------------------------------------------------
echo "=========================================="
echo " Miniconda3 Lightweight Installer"
echo " Target path: ${MINICONDA_DIR}"
echo "=========================================="

run_prechecks

echo "------------------------------------------"
log_info "Downloading Miniconda installer (~140 MB)..."
curl -# -L "${INSTALLER_URL}" -o "${INSTALLER}"

# Verify file header
if [[ ! -s "${INSTALLER}" ]] || ! head -n 1 "${INSTALLER}" | grep -q "sh"; then
    log_err "Downloaded file is corrupted or invalid."
    rm -f "${INSTALLER}"
    exit 1
fi

log_info "Installing Miniconda3 (-b)..."
bash "${INSTALLER}" -b -p "${MINICONDA_DIR}"

log_info "Removing installer..."
rm -f "${INSTALLER}"

log_info "Initializing Conda for Bash..."
"${MINICONDA_DIR}/bin/conda" init bash

log_info "Disabling auto-activation of base environment..."
"${MINICONDA_DIR}/bin/conda" config --set auto_activate_base false

echo "=========================================="
log_pass "Miniconda3 installed at: ${MINICONDA_DIR}"
echo "To use conda, run:"
echo "    source ~/.bashrc"
echo "Then activate environments when needed:"
echo "    conda activate <env_name>"
echo "=========================================="
