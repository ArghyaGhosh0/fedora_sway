#!/usr/bin/env bash
set -euo pipefail

# Determine script root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/configs"

# Global flags
FLAG_ALL=false
FLAG_DRY_RUN=false
FLAG_SYMLINK=false

# --------------------------------------------------
# Helper Functions
# --------------------------------------------------
log_info() { echo -e "\033[1;34m[*] $1\033[0m"; }
log_warn() { echo -e "\033[1;33m[!] $1\033[0m"; }
log_skip() { echo -e "\033[1;30m[-] Skipped: $1\033[0m"; }
log_done() { echo -e "\033[1;32m[✓] $1\033[0m"; }

prompt_user() {
    local task_name="$1"
    if [[ "${FLAG_ALL}" == true ]]; then
        return 0
    fi
    read -r -p "[?] Do you want to run: ${task_name}? (y/N): " choice
    case "${choice}" in
        y|Y ) return 0 ;;
        * ) return 1 ;;
    esac
}

run_dnf_install() {
    local label="$1"
    shift
    local pkgs=("$@")

    if prompt_user "Install ${label} (${pkgs[*]})"; then
        log_info "Installing: ${pkgs[*]}..."
        if [[ "${FLAG_DRY_RUN}" == true ]]; then
            log_info "[DRY-RUN] sudo dnf install -y ${pkgs[*]}"
            return 0
        fi
        sudo dnf install -y "${pkgs[@]}"
        log_done "${label} installed."
    else
        log_skip "${label} installation"
    fi
}

deploy_file() {
    local src="$1"
    local dest="$2"

    if [[ ! -f "${src}" ]]; then
        log_warn "Source file ${src} does not exist. Skipping."
        return 1
    fi

    if [[ "${FLAG_DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] Deploy ${src} -> ${dest}"
        return 0
    fi

    mkdir -p "$(dirname "${dest}")"

    # Backup existing file if not a link
    if [[ -f "${dest}" && ! -L "${dest}" ]]; then
        cp "${dest}" "${dest}.bak.$(date +%s)"
    fi

    if [[ "${FLAG_SYMLINK}" == true ]]; then
        ln -sf "${src}" "${dest}"
        log_done "Symlinked ${src} -> ${dest}"
    else
        cp "${src}" "${dest}"
        log_done "Copied ${src} -> ${dest}"
    fi
}

show_help() {
    cat <<EOF
Usage: ./install.sh [OPTIONS]

Options:
    -a, --all         Run all installation tasks without prompting
    -s, --symlink     Symlink configs instead of copying (ideal for active dotfiles)
    -d, --dry-run     Show actions without executing commands or modifying files
    --upgrade         Run system upgrade only
    --packages        Run granular package install prompts only
    --python312       Install Python 3.12 and set user defaults only
    --git             Run git configuration only
    --theme           Run GTK dark theme setup only
    --sway            Run Sway WM setup only
    --nvim            Run Neovim setup only
    --timeshift       Run Timeshift snapshot only
    -h, --help        Show this help message
EOF
}

# --------------------------------------------------
# Task Modules
# --------------------------------------------------
task_system_upgrade() {
    if prompt_user "System Full Upgrade (dnf upgrade)"; then
        log_info "Running full system upgrade..."
        if [[ "${FLAG_DRY_RUN}" == true ]]; then
            log_info "[DRY-RUN] sudo dnf upgrade -y"
            return 0
        fi
        sudo dnf upgrade -y
        log_done "System upgrade complete."
    else
        log_skip "System Upgrade"
    fi
}

task_packages() {
    echo "--- Package Selection ---"
    run_dnf_install "Core Tools" git neovim
    run_dnf_install "C/C++ Build Toolchain" gcc gcc-c++ clang-tools-extra
    run_dnf_install "Search Utilities (ripgrep, fd)" ripgrep fd-find
    run_dnf_install "Backup Utility (Timeshift)" timeshift
}

task_python312() {
    if prompt_user "Install Python 3.12 & set as user-level default"; then
        log_info "Installing Python 3.12 via dnf..."
        if [[ "${FLAG_DRY_RUN}" == true ]]; then
            log_info "[DRY-RUN] sudo dnf install -y python3.12 python3.12-devel"
            log_info "[DRY-RUN] python3.12 -m ensurepip --upgrade"
            log_info "[DRY-RUN] Link python3.12 -> ~/.local/bin/python & python3"
            return 0
        fi

        # Install runtime and development headers
        sudo dnf install -y python3.12 python3.12-devel

        # Bootstrap pip for 3.12
        python3.12 -m ensurepip --default-pip --user

        # Create symlinks in ~/.local/bin
        mkdir -p "${HOME}/.local/bin"
        ln -sf /usr/bin/python3.12 "${HOME}/.local/bin/python"
        ln -sf /usr/bin/python3.12 "${HOME}/.local/bin/python3"

        # Ensure PATH is exported in ~/.bashrc
        if ! grep -q 'export PATH="\$HOME/\.local/bin:\$PATH"' "${HOME}/.bashrc"; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "${HOME}/.bashrc"
        fi

        log_done "Python 3.12 configured as user default in ~/.local/bin."
    else
        log_skip "Python 3.12 Installation & Setup"
    fi
}

task_git() {
    if prompt_user "Git Configuration (Arghya Ghosh)"; then
        log_info "Configuring Git profile..."
        if [[ "${FLAG_DRY_RUN}" == false ]]; then
            git config --global user.name "Arghya Ghosh"
            git config --global user.email "ubuntuuser33@gmail.com"
        fi
        log_done "Git configured."
    else
        log_skip "Git Configuration"
    fi
}

task_theme() {
    if prompt_user "Dark Theme & GTK Preferences"; then
        log_info "Applying dark theme..."
        if [[ "${FLAG_DRY_RUN}" == false ]]; then
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
            gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || true
        fi
        deploy_file "${CONFIG_DIR}/gtk/settings.ini" "${HOME}/.config/gtk-3.0/settings.ini"
        log_done "Dark theme configured."
    else
        log_skip "Dark Theme Preferences"
    fi
}

task_sway() {
    if prompt_user "Sway Window Manager Configuration"; then
        log_info "Configuring Sway..."
        local sway_config="${HOME}/.config/sway/config"
        local sway_dir="${HOME}/.config/sway"

        if [[ "${FLAG_DRY_RUN}" == false ]]; then
            mkdir -p "${sway_dir}"
            if [[ ! -f "${sway_config}" ]]; then
                if [[ -f "/etc/sway/config" ]]; then
                    cp /etc/sway/config "${sway_config}"
                else
                    touch "${sway_config}"
                fi
            fi

            deploy_file "${CONFIG_DIR}/sway/touchpad.conf" "${sway_dir}/touchpad.conf"
            deploy_file "${CONFIG_DIR}/sway/theme.conf" "${sway_dir}/theme.conf"

            if ! grep -q 'include touchpad.conf' "${sway_config}"; then
                echo "include touchpad.conf" >> "${sway_config}"
            fi
            if ! grep -q 'include theme.conf' "${sway_config}"; then
                echo "include theme.conf" >> "${sway_config}"
            fi
        fi
        log_done "Sway modular configuration installed."
    else
        log_skip "Sway Configuration"
    fi
}

task_nvim() {
    if prompt_user "Neovim Setup (init.lua)"; then
        log_info "Installing Neovim config from ${CONFIG_DIR}/nvim/init.lua..."
        deploy_file "${CONFIG_DIR}/nvim/init.lua" "${HOME}/.config/nvim/init.lua"
        log_done "Neovim configured."
    else
        log_skip "Neovim Setup"
    fi
}

task_timeshift() {
    if prompt_user "Timeshift Initial Snapshot"; then
        log_info "Creating initial Timeshift snapshot (RSYNC)..."
        if [[ "${FLAG_DRY_RUN}" == false ]]; then
            sudo timeshift --create --comments "Post-install baseline" --tags D || log_warn "Timeshift snapshot skipped or failed."
        fi
        log_done "Timeshift snapshot complete."
    else
        log_skip "Timeshift Snapshot"
    fi
}

task_sway_reload() {
    if command -v swaymsg >/dev/null 2>&1 && [[ -n "${SWAYSOCK:-}" ]]; then
        if prompt_user "Reload Sway Configuration Now"; then
            log_info "Reloading Sway..."
            [[ "${FLAG_DRY_RUN}" == false ]] && swaymsg reload || true
            log_done "Sway reloaded."
        fi
    fi
}

# --------------------------------------------------
# Argument Parsing & Dispatcher
# --------------------------------------------------
SINGLE_TASK=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--all) FLAG_ALL=true; shift ;;
        -s|--symlink) FLAG_SYMLINK=true; shift ;;
        -d|--dry-run) FLAG_DRY_RUN=true; shift ;;
        --upgrade) SINGLE_TASK="system_upgrade"; shift ;;
        --packages) SINGLE_TASK="packages"; shift ;;
        --python312) SINGLE_TASK="python312"; shift ;;
        --git) SINGLE_TASK="git"; shift ;;
        --theme) SINGLE_TASK="theme"; shift ;;
        --sway) SINGLE_TASK="sway"; shift ;;
        --nvim) SINGLE_TASK="nvim"; shift ;;
        --timeshift) SINGLE_TASK="timeshift"; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

echo "=========================================="
echo " Fedora Linux Setup Engine"
[[ "${FLAG_DRY_RUN}" == true ]] && echo " MODE: DRY RUN (No changes will be written)"
[[ "${FLAG_SYMLINK}" == true ]] && echo " MODE: SYMLINK (Linking dotfiles directly)"
echo "=========================================="

if [[ -n "${SINGLE_TASK}" ]]; then
    "task_${SINGLE_TASK}"
else
    task_system_upgrade
    task_packages
    task_python312
    task_git
    task_theme
    task_sway
    task_nvim
    task_timeshift
    task_sway_reload
fi

echo "=========================================="
log_done "Script run finished."
echo "=========================================="
