#!/usr/bin/env bash
set -euo pipefail

SWAY_CONFIG="${HOME}/.config/sway/config"
WALLPAPER_DIR="${HOME}/fedora_sway/wallpaper_img"

# 1. Resolve an actual image file from the directory (handling .png, .jpg, etc.)
WALLPAPER_PATH=$(find "${WALLPAPER_DIR}" -maxdepth 1 -type f \( -name "wallpaper.png" -o -name "wallpaper.jpg" -o -name "wallpaper.jpeg" -o -name "wallpaper.webp" \) | head -n 1)

if [[ -z "${WALLPAPER_PATH}" ]]; then
    echo "Error: No valid wallpaper image found in ${WALLPAPER_DIR}" >&2
    
    exit 1
fi

TARGET_DIRECTIVE="output * bg ${WALLPAPER_PATH} fill"

# 2. Check if Sway config file exists
if [[ ! -f "${SWAY_CONFIG}" ]]; then
    echo "Error: Config file not found at ${SWAY_CONFIG}" >&2
    exit 1
fi

# 3. Check if an 'output * bg' line already exists (safe under set -e)
if grep -qE '^output \* bg' "${SWAY_CONFIG}"; then
    # Replace the existing line with the updated wallpaper path
    sed -i "s|^output \* bg.*|${TARGET_DIRECTIVE}|" "${SWAY_CONFIG}"
else
    # Append to config if not present
    echo "" >> "${SWAY_CONFIG}"
    echo "${TARGET_DIRECTIVE}" >> "${SWAY_CONFIG}"
fi

# 4. Reload Sway to apply changes
swaymsg reload
