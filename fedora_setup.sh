#!/usr/bin/env bash
set -euo pipefail

prompt_user() {
    local task_name="$1"
    read -p "[?] Do you want to run: $task_name? (y/N): " choice
    case "$choice" in 
        y|Y ) return 0 ;;
        * ) return 1 ;;
    esac
}

echo "=========================================="
echo " Starting Interactive Fedora Setup"
echo "=========================================="

# --------------------------------------------------
# 1. System Upgrade & Core Package Installation
# --------------------------------------------------
if prompt_user "System Upgrade & Core Package Installation"; then
    echo "[*] Upgrading system packages..."
    sudo dnf upgrade -y

    echo "[*] Installing Timeshift, Neovim, Git, and build tools..."
    sudo dnf install -y \
        timeshift \
        neovim \
        git \
        gcc \
        gcc-c++ \
        python3 \
        python3-pip \
        ripgrep \
        fd-find \
        clang-tools-extra
else
    echo "[skipped] System Upgrade & Core Packages"
fi

# --------------------------------------------------
# 2. Git Configuration
# --------------------------------------------------
if prompt_user "Git Configuration (Arghya Ghosh)"; then
    echo "[*] Configuring Git user profile..."
    git config --global user.name "Arghya Ghosh"
    git config --global user.email "ubuntuuser33@gmail.com"
else
    echo "[skipped] Git Configuration"
fi

# --------------------------------------------------
# 3. Dark Theme & GTK Configuration
# --------------------------------------------------
if prompt_user "Dark Theme & GTK Preferences"; then
    echo "[*] Setting dark theme preferences..."
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || true

    mkdir -p "$HOME/.config/gtk-3.0"
    cat <<'EOF' > "$HOME/.config/gtk-3.0/settings.ini"
[Settings]
gtk-theme-name=Adwaita-dark
gtk-application-prefer-dark-theme=1
EOF
else
    echo "[skipped] Dark Theme Configuration"
fi

# --------------------------------------------------
# 4. Sway Configuration (Touchpad & Theme Colors)
# --------------------------------------------------
if prompt_user "Sway Window Manager Configuration"; then
    echo "[*] Configuring Sway..."
    SWAY_CONFIG_DIR="$HOME/.config/sway"
    SWAY_CONFIG="$SWAY_CONFIG_DIR/config"
    mkdir -p "$SWAY_CONFIG_DIR"

    if [ ! -f "$SWAY_CONFIG" ]; then
        if [ -f "/etc/sway/config" ]; then
            cp /etc/sway/config "$SWAY_CONFIG"
        else
            touch "$SWAY_CONFIG"
        fi
    fi

    if ! grep -q 'type:touchpad' "$SWAY_CONFIG"; then
        cat <<'EOF' >> "$SWAY_CONFIG"

# Touchpad configuration
input "type:touchpad" {
    tap enabled
    natural_scroll enabled
}
EOF
    fi

    if ! grep -q 'client.focused' "$SWAY_CONFIG"; then
        cat <<'EOF' >> "$SWAY_CONFIG"

# Window color definitions
client.focused          #333333 #222222 #ffffff #555555    #333333
client.focused_inactive #222222 #1a1a1a #888888 #222222    #222222
client.unfocused        #1a1a1a #141414 #666666 #1a1a1a    #1a1a1a
client.urgent           #900000 #900000 #ffffff #900000    #900000
EOF
    fi
else
    echo "[skipped] Sway Configuration"
fi

# --------------------------------------------------
# 5. Neovim Configuration (init.lua)
# --------------------------------------------------
if prompt_user "Neovim Setup & Plugins (init.lua)"; then
    echo "[*] Setting up Neovim configuration..."
    NVIM_DIR="$HOME/.config/nvim"
    mkdir -p "$NVIM_DIR"

    cat <<'EOF' > "$NVIM_DIR/init.lua"
-- 1. CORE OPTIONS & GENERAL SETTINGS
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local opt = vim.opt

-- Line numbering
opt.number = true
opt.relativenumber = true

-- Tabs & Indentation
opt.tabstop = 4
opt.softtabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.smartindent = true

-- Search behavior
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = false
opt.incsearch = true

-- UI & Display
opt.termguicolors = true
opt.scrolloff = 8
opt.signcolumn = "yes"
opt.cursorline = true
opt.wrap = false

-- System & Performance
opt.clipboard = "unnamedplus"
opt.undofile = true
opt.swapfile = false
opt.backup = false
opt.updatetime = 250
opt.timeoutlen = 300
opt.splitright = true
opt.splitbelow = true

-- 2. BASIC QUALITY-OF-LIFE KEYMAPS
local map = vim.keymap.set

map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move lines down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move lines up" })
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")
map("v", "<", "<gv")
map("v", ">", ">gv")
map("n", "<C-h>", "<C-w>h", { desc = "Focus left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Focus lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Focus upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Focus right window" })
map("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- 3. BOOTSTRAP LAZY.NVIM
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-- 4. PLUGINS SETUP
require("lazy").setup({
    {
        "catppuccin/nvim",
        name = "catppuccin",
        priority = 1000,
        config = function()
            require("catppuccin").setup({ flavour = "mocha" })
            vim.cmd.colorscheme("catppuccin")
        end,
    },
    {
        "nvim-lualine/lualine.nvim",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        opts = { options = { theme = "catppuccin", icons_enabled = true } },
    },
    {
        "lewis6991/gitsigns.nvim",
        opts = {},
    },
    {
        "windwp/nvim-autopairs",
        event = "InsertEnter",
        opts = {},
    },
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        config = function()
            require("nvim-treesitter.configs").setup({
                ensure_installed = { "c", "cpp", "python", "lua", "vim", "vimdoc", "bash", "markdown" },
                auto_install = true,
                highlight = { enable = true },
                indent = { enable = true },
            })
        end,
    },
    {
        "nvim-telescope/telescope.nvim",
        tag = "0.1.8",
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            local builtin = require("telescope.builtin")
            map("n", "<leader>ff", builtin.find_files, { desc = "Find Files" })
            map("n", "<leader>fg", builtin.live_grep, { desc = "Live Grep" })
            map("n", "<leader>fb", builtin.buffers, { desc = "Find Buffers" })
            map("n", "<leader>fh", builtin.help_tags, { desc = "Help Tags" })
        end,
    },
    {
        "stevearc/conform.nvim",
        event = { "BufWritePre" },
        cmd = { "ConformInfo" },
        keys = {
            {
                "<leader>f",
                function()
                    require("conform").format({ async = true, lsp_fallback = true })
                end,
                mode = "",
                desc = "Format buffer",
            },
        },
        opts = {
            formatters_by_ft = {
                c = { "clang-format" },
                cpp = { "clang-format" },
                python = { "ruff_format", "ruff_fix" },
                lua = { "stylua" },
            },
            format_on_save = {
                timeout_ms = 500,
                lsp_fallback = true,
            },
        },
    },
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            "williamboman/mason.nvim",
            "williamboman/mason-lspconfig.nvim",
            "hrsh7th/cmp-nvim-lsp",
        },
        config = function()
            require("mason").setup()
            require("mason-lspconfig").setup({
                ensure_installed = { "clangd", "basedpyright", "lua_ls" },
                automatic_installation = true,
            })

            local lspconfig = require("lspconfig")
            local capabilities = require("cmp_nvim_lsp").default_capabilities()

            local on_attach = function(_, bufnr)
                local bmap = function(mode, keys, func, desc)
                    vim.keymap.set(mode, keys, func, { buffer = bufnr, desc = desc })
                end
                bmap("n", "gd", vim.lsp.buf.definition, "Go to Definition")
                bmap("n", "gr", vim.lsp.buf.references, "Go to References")
                bmap("n", "gI", vim.lsp.buf.implementation, "Go to Implementation")
                bmap("n", "K", vim.lsp.buf.hover, "Hover Documentation")
                bmap("n", "<leader>rn", vim.lsp.buf.rename, "Rename Symbol")
                bmap("n", "<leader>ca", vim.lsp.buf.code_action, "Code Action")
                bmap("n", "[d", vim.diagnostic.goto_prev, "Previous Diagnostic")
                bmap("n", "]d", vim.diagnostic.goto_next, "Next Diagnostic")
                bmap("n", "<leader>d", vim.diagnostic.open_float, "Show Diagnostic Error")
            end

            lspconfig.clangd.setup({ on_attach = on_attach, capabilities = capabilities })
            lspconfig.basedpyright.setup({ on_attach = on_attach, capabilities = capabilities })
            lspconfig.lua_ls.setup({ on_attach = on_attach, capabilities = capabilities })
        end,
    },
    {
        "hrsh7th/nvim-cmp",
        event = "InsertEnter",
        dependencies = {
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-path",
            "L3MON4D3/LuaSnip",
            "saadparwaiz1/cmp_luasnip",
        },
        config = function()
            local cmp = require("cmp")
            local luasnip = require("luasnip")

            cmp.setup({
                snippet = {
                    expand = function(args)
                        luasnip.lsp_expand(args.body)
                    end,
                },
                mapping = cmp.mapping.preset.insert({
                    ["<C-n>"] = cmp.mapping.select_next_item(),
                    ["<C-p>"] = cmp.mapping.select_prev_item(),
                    ["<CR>"] = cmp.mapping.confirm({ select = true }),
                }),
                sources = cmp.config.sources({
                    { name = "nvim_lsp" },
                    { name = "luasnip" },
                    { name = "path" },
                }, {
                    { name = "buffer" },
                }),
            })
        end,
    },
})
EOF
else
    echo "[skipped] Neovim Setup"
fi

# --------------------------------------------------
# 6. Timeshift Initial Snapshot
# --------------------------------------------------
if prompt_user "Timeshift Initial Snapshot"; then
    echo "[*] Creating an initial Timeshift snapshot (RSYNC)..."
    sudo timeshift --create --comments "Post-install baseline" --tags D || echo "[!] Timeshift snapshot skipped."
else
    echo "[skipped] Timeshift Snapshot"
fi

# --------------------------------------------------
# 7. Reload Sway Configuration
# --------------------------------------------------
if command -v swaymsg >/dev/null 2>&1 && [ -n "${SWAYSOCK:-}" ]; then
    if prompt_user "Reload Sway Configuration"; then
        echo "[*] Reloading Sway configuration..."
        swaymsg reload || true
    fi
fi

echo "=========================================="
echo " Setup complete! Reopen your terminal or reload Sway (\$mod+Shift+c)."
echo "=========================================="
