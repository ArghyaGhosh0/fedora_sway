#!/usr/bin/env bash
set -euo pipefail

DEST_BIN="${HOME}/.local/bin/purge-all"
CURRENT_SCRIPT="$(realpath "$0")"

# -----------------------------------------------------------------------------
# Self-Deploy / Path Guard
# -----------------------------------------------------------------------------
# If not running from ~/.local/bin/purge-all, handle self-installation
if [[ "${CURRENT_SCRIPT}" != "${DEST_BIN}" ]]; then
    mkdir -p "${HOME}/.local/bin"

    if [[ -f "${DEST_BIN}" ]]; then
        echo -e "\033[1;33m[!] 'purge-all' is already installed in ~/.local/bin.\033[0m"
        echo -e "You can run it directly from anywhere:\n"
        echo -e "    \033[1;32mpurge-all ${*:-<target_name>}\033[0m\n"
    else
        cp "${CURRENT_SCRIPT}" "${DEST_BIN}"
        chmod +x "${DEST_BIN}"
        echo -e "\033[1;32m[✓] Installed 'purge-all' to ~/.local/bin/purge-all.\033[0m"
        echo -e "Run it directly from anywhere:\n"
        echo -e "    \033[1;32mpurge-all ${*:-<target_name>}\033[0m\n"
        
        # Check if ~/.local/bin is in PATH
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            echo -e "\033[1;33m[!] Note: Ensure ~/.local/bin is in your PATH (e.g., in ~/.bashrc):\033[0m"
            echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
        fi
    fi
    exit 0
fi

# -----------------------------------------------------------------------------
# Core Purge Logic (Runs only when executed as ~/.local/bin/purge-all)
# -----------------------------------------------------------------------------
TARGET=""
DRY_RUN=false
FORCE=false

declare -ra PROTECTED_DIRS=(
    "/" "/bin" "/boot" "/dev" "/etc" "/home" "${HOME}"
    "${HOME}/.config" "${HOME}/.cache" "${HOME}/.local"
    "${HOME}/.local/share" "${HOME}/.local/state" "${HOME}/.local/bin"
    "/lib" "/lib64" "/opt" "/proc" "/root" "/run" "/sbin"
    "/sys" "/tmp" "/usr" "/usr/bin" "/usr/lib" "/usr/local"
    "/usr/local/bin" "/var" "/var/log" "/var/tmp"
)

log_info()  { echo -e "\033[1;34m[*] $1\033[0m"; }
log_warn()  { echo -e "\033[1;33m[!] $1\033[0m"; }
log_err()   { echo -e "\033[1;31m[✗] $1\033[0m" >&2; }
log_pass()  { echo -e "\033[1;32m[✓] $1\033[0m"; }
log_item()  { echo -e "    \033[0;36m->\033[0m $1"; }

is_protected() {
    local candidate
    candidate="$(realpath -m "$1")"
    for protected in "${PROTECTED_DIRS[@]}"; do
        if [[ "${candidate}" == "${protected}" ]]; then
            return 0
        fi
    done
    return 1
}

validate_target() {
    if [[ -z "${TARGET}" ]]; then
        log_err "No target specified."
        echo "Usage: purge-all [-d|--dry-run] [-f|--force] <target_name>"
        exit 1
    fi
    if [[ "${TARGET}" =~ [/\\*] || "${TARGET}" == "." || "${TARGET}" == ".." ]]; then
        log_err "Target '${TARGET}' contains illegal characters."
        exit 1
    fi
    if [[ ${#TARGET} -lt 3 ]]; then
        log_err "Target name '${TARGET}' is too short (min 3 chars required)."
        exit 1
    fi
}

declare -a SEARCH_TERMS=()

resolve_aliases() {
    local lower_target
    lower_target=$(echo "${TARGET}" | tr '[:upper:]' '[:lower:]')
    SEARCH_TERMS+=("${lower_target}")

    if [[ "${lower_target}" =~ (conda|anaconda|miniconda) ]]; then
        SEARCH_TERMS+=("conda" "anaconda" "miniconda" "continuum")
    fi
    if [[ "${lower_target}" =~ (rust|cargo|rustup) ]]; then
        SEARCH_TERMS+=("cargo" "rustup" "rust")
    fi
    if [[ "${lower_target}" =~ (node|npm|nvm|yarn) ]]; then
        SEARCH_TERMS+=("node" "npm" "nvm" "yarn")
    fi

    mapfile -t SEARCH_TERMS < <(printf "%s\n" "${SEARCH_TERMS[@]}" | sort -u)
}

declare -a FOUND_PIDS=()
declare -a FOUND_PROC_NAMES=()
declare -a FOUND_FILES_USER=()
declare -a FOUND_FILES_SYSTEM=()

add_user_path() {
    local p="$1"
    if [[ -e "${p}" ]] && ! is_protected "${p}"; then
        for existing in "${FOUND_FILES_USER[@]:-}"; do
            [[ "${existing}" == "${p}" ]] && return 0
        done
        FOUND_FILES_USER+=("${p}")
    fi
}

add_sys_path() {
    local p="$1"
    if [[ -e "${p}" ]] && ! is_protected "${p}"; then
        for existing in "${FOUND_FILES_SYSTEM[@]:-}"; do
            [[ "${existing}" == "${p}" ]] && return 0
        done
        FOUND_FILES_SYSTEM+=("${p}")
    fi
}

discover_traces() {
    log_info "Auditing system for target '${TARGET}' (ecosystem terms: ${SEARCH_TERMS[*]})..."

    for term in "${SEARCH_TERMS[@]}"; do
        while read -r pid comm; do
            if [[ -n "${pid}" && "${pid}" != "$$" && "${pid}" != "$PPID" ]]; then
                case "${comm}" in
                    *bash*|*zsh*|*fish*|*sway*|*foot*|*alacritty*|*gnome-terminal*)
                        continue
                        ;;
                    *)
                        FOUND_PIDS+=("${pid}")
                        FOUND_PROC_NAMES+=("${pid} ${comm}")
                        ;;
                esac
            fi
        done < <(pgrep -fa "${term}" 2>/dev/null || true)

        local scan_roots=(
            "${HOME}"
            "${HOME}/.config"
            "${HOME}/.cache"
            "${HOME}/.local/share"
            "${HOME}/.local/state"
            "${HOME}/.local/bin"
        )

        for sroot in "${scan_roots[@]}"; do
            if [[ -d "${sroot}" ]]; then
                while IFS= read -r match; do
                    add_user_path "${match}"
                done < <(find "${sroot}" -maxdepth 1 \( -iname "*${term}*" -o -iname ".*${term}*" \) 2>/dev/null || true)
            fi
        done

        local sys_roots=("/opt" "/etc" "/tmp" "/var/tmp" "/usr/local/bin")
        for sroot in "${sys_roots[@]}"; do
            if [[ -d "${sroot}" ]]; then
                while IFS= read -r match; do
                    add_sys_path "${match}"
                done < <(find "${sroot}" -maxdepth 1 -iname "*${term}*" 2>/dev/null || true)
            fi
        done
    done
}

display_summary() {
    echo "=========================================================="
    echo -e " AUDIT REPORT FOR TARGET: \033[1;36m${TARGET}\033[0m"
    echo "=========================================================="

    local total_items=0

    if [[ ${#FOUND_PROC_NAMES[@]} -gt 0 ]]; then
        echo -e "\033[1;33m[Active Processes Detected]\033[0m"
        for proc in "${FOUND_PROC_NAMES[@]}"; do
            log_item "${proc}"
            total_items=$((total_items + 1))
        done
    fi

    if [[ ${#FOUND_FILES_USER[@]} -gt 0 ]]; then
        echo -e "\033[1;33m[User Files & Directories To Delete]\033[0m"
        for f in "${FOUND_FILES_USER[@]}"; do
            local size
            size=$(du -sh "${f}" 2>/dev/null | cut -f1 || echo "unknown")
            log_item "${f} (${size})"
            total_items=$((total_items + 1))
        done
    fi

    if [[ ${#FOUND_FILES_SYSTEM[@]} -gt 0 ]]; then
        echo -e "\033[1;33m[System Files To Delete]\033[0m"
        for f in "${FOUND_FILES_SYSTEM[@]}"; do
            local size
            size=$(du -sh "${f}" 2>/dev/null | cut -f1 || echo "unknown")
            log_item "${f} (${size})"
            total_items=$((total_items + 1))
        done
    fi

    echo "=========================================================="
    if [[ "${total_items}" -eq 0 ]]; then
        log_pass "Clean! No matching processes, configs, caches, or files found."
        exit 0
    else
        log_warn "Total items detected: ${total_items}"
    fi
}

execute_purge() {
    if [[ ${#FOUND_PIDS[@]} -gt 0 ]]; then
        log_info "Terminating active processes..."
        kill -15 "${FOUND_PIDS[@]}" 2>/dev/null || true
        sleep 1
    fi

    if [[ ${#FOUND_FILES_USER[@]} -gt 0 ]]; then
        log_info "Deleting user files and directories..."
        for f in "${FOUND_FILES_USER[@]}"; do
            if ! is_protected "${f}"; then
                rm -rf "${f}"
                log_pass "Deleted: ${f}"
            fi
        done
    fi

    if [[ ${#FOUND_FILES_SYSTEM[@]} -gt 0 ]]; then
        log_info "Deleting system files..."
        for f in "${FOUND_FILES_SYSTEM[@]}"; do
            if ! is_protected "${f}"; then
                sudo rm -rf "${f}"
                log_pass "Deleted (sudo): ${f}"
            fi
        done
    fi

    if [[ "${TARGET}" =~ (conda|anaconda|miniconda) ]] && [[ -f "${HOME}/.bashrc" ]]; then
        if grep -q "conda initialize" "${HOME}/.bashrc"; then
            log_info "Scrubbing conda initialization blocks from ~/.bashrc..."
            sed -i '/# >>> conda initialize >>>/,/# <<< conda initialize <<</d' "${HOME}/.bashrc"
            log_pass "Cleaned ~/.bashrc"
        fi
    fi

    echo "----------------------------------------------------------"
    log_pass "Purge complete for '${TARGET}'."
}

# -----------------------------------------------------------------------------
# Entry Point
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dry-run) DRY_RUN=true; shift ;;
        -f|--force)   FORCE=true; shift ;;
        *)            TARGET="$1"; shift ;;
    esac
done

validate_target
resolve_aliases
discover_traces
display_summary

if [[ "${DRY_RUN}" == true ]]; then
    log_info "Dry run complete. No modifications made."
    exit 0
fi

if [[ "${FORCE}" == false ]]; then
    echo ""
    read -r -p "Type 'yes' to permanently delete all items listed above: " confirm
    if [[ "${confirm}" != "yes" ]]; then
        log_warn "Aborted by user."
        exit 0
    fi
fi

execute_purge
