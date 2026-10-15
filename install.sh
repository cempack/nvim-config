#!/usr/bin/env bash
# Install Neovim and this LazyVim configuration. Safe to re-run: whatever is
# already installed is upgraded or backed up, never silently clobbered.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/cempack/nvim-config/main/install.sh)
#
# Options:
#   --no-deps   skip system package installation (no sudo)
#   --force     back up the existing config and re-clone even if it is this repo
set -euo pipefail

REPO_URL="${NVIM_CONFIG_REPO:-https://github.com/cempack/nvim-config.git}"
BRANCH="${NVIM_CONFIG_BRANCH:-main}"
EPITECH_URL="${EPITECH_DUMP_REPO:-https://github.com/cempack/epitech-dump-arch.git}"
MIN_NVIM="0.11.2"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
CONFIG_DIR="$CONFIG_HOME/nvim"
LOCAL_BIN="$HOME/.local/bin"
ORIG_PATH="$PATH"
STAMP="$(date +%Y%m%d-%H%M%S)"

INSTALL_DEPS=1
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --no-deps) INSTALL_DEPS=0 ;;
        --force) FORCE=1 ;;
        -h|--help) echo "usage: install.sh [--no-deps] [--force]"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merr\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- System packages --------------------------------------------------------

install_packages() {
    log "Installing system dependencies"
    if have pacman; then
        $SUDO pacman -S --needed --noconfirm neovim git curl unzip ripgrep fd gcc make \
            tree-sitter-cli clang
    elif have apt-get; then
        # Debian/Ubuntu's neovim is usually too old; the release tarball is used below.
        $SUDO apt-get update -y
        $SUDO apt-get install -y git curl unzip tar gzip ripgrep fd-find build-essential \
            clang-format
        if have fdfind && ! have fd; then
            mkdir -p "$LOCAL_BIN" && ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"
        fi
    elif have dnf; then
        $SUDO dnf install -y neovim git curl unzip ripgrep fd-find gcc make tree-sitter-cli \
            clang-tools-extra
    elif have zypper; then
        $SUDO zypper --non-interactive install neovim git curl unzip ripgrep fd gcc make \
            tree-sitter clang
    elif have brew; then
        brew install neovim git ripgrep fd clang-format
        brew install tree-sitter-cli 2>/dev/null || brew install tree-sitter || true
    else
        warn "no supported package manager found; install git, curl, ripgrep, fd and a C compiler yourself"
    fi
}

# --- Neovim -----------------------------------------------------------------

nvim_ok() {
    have nvim && nvim --clean --headless -u NONE \
        "+lua if vim.fn.has('nvim-$MIN_NVIM') == 0 then vim.cmd('cquit 1') end" +qa \
        >/dev/null 2>&1
}

install_nvim_release() {
    local arch
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64) arch="x86_64" ;;
        Linux-aarch64|Linux-arm64) arch="arm64" ;;
        *) die "no prebuilt Neovim for $(uname -s)-$(uname -m); install Neovim >= $MIN_NVIM manually" ;;
    esac
    log "Installing the latest Neovim release into ~/.local"
    curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$arch.tar.gz" \
        -o "$TMP/nvim.tar.gz"
    rm -rf "$HOME/.local/opt/nvim"
    mkdir -p "$HOME/.local/opt/nvim" "$LOCAL_BIN"
    tar -xzf "$TMP/nvim.tar.gz" -C "$HOME/.local/opt/nvim" --strip-components=1
    ln -sf "$HOME/.local/opt/nvim/bin/nvim" "$LOCAL_BIN/nvim"
}

ensure_nvim() {
    export PATH="$LOCAL_BIN:$PATH"
    if ! nvim_ok; then
        install_nvim_release
        hash -r
    fi
    nvim_ok || die "Neovim >= $MIN_NVIM is required but $(command -v nvim || echo nvim) is older or missing"
    ok "$(nvim --version | head -n1) ($(command -v nvim))"
    if [ "$(PATH="$ORIG_PATH" command -v nvim 2>/dev/null)" != "$(command -v nvim)" ]; then
        warn "open a new login shell (or add $LOCAL_BIN to the front of PATH) to use this nvim"
    fi
}

# nvim-treesitter (main branch) compiles parsers with the tree-sitter CLI.
ensure_tree_sitter() {
    have tree-sitter && return
    local asset
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64) asset="tree-sitter-linux-x64.gz" ;;
        Linux-aarch64|Linux-arm64) asset="tree-sitter-linux-arm64.gz" ;;
        *) warn "tree-sitter CLI missing; treesitter parsers may fail to build"; return ;;
    esac
    log "Installing the tree-sitter CLI into $LOCAL_BIN"
    mkdir -p "$LOCAL_BIN"
    if curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/latest/download/$asset" \
        | gunzip > "$LOCAL_BIN/tree-sitter"; then
        chmod +x "$LOCAL_BIN/tree-sitter"
        if ! "$LOCAL_BIN/tree-sitter" --version >/dev/null 2>&1; then
            rm -f "$LOCAL_BIN/tree-sitter"
            warn "downloaded tree-sitter CLI does not run here; treesitter parsers may fail to build"
        fi
    else
        rm -f "$LOCAL_BIN/tree-sitter"
        warn "tree-sitter CLI download failed; treesitter parsers may fail to build"
    fi
}

# --- Configuration ----------------------------------------------------------

backup() {
    local path="$1"
    if [ -e "$path" ] || [ -L "$path" ]; then
        mv "$path" "$path.bak.$STAMP"
        warn "moved $path -> $path.bak.$STAMP"
    fi
}

is_this_repo() {
    [ -d "$CONFIG_DIR/.git" ] || return 1
    local url
    url="$(git -C "$CONFIG_DIR" remote get-url origin 2>/dev/null)" || return 1
    case "$url" in
        *cempack/nvim-config|*cempack/nvim-config.git) return 0 ;;
        *) return 1 ;;
    esac
}

# Clone into a temp dir first so a failed clone never leaves you without a config.
fetch_config() {
    log "Cloning $REPO_URL"
    git clone -q --branch "$BRANCH" "$REPO_URL" "$TMP/config" \
        || die "could not clone $REPO_URL"
}

place_config() {
    mkdir -p "$CONFIG_HOME"
    mv "$TMP/config" "$CONFIG_DIR"
}

install_config() {
    if [ "$FORCE" -eq 0 ] && is_this_repo; then
        log "Config already installed; updating it"
        # lazy.nvim rewrites the lockfile on its own; the repo's copy is authoritative.
        git -C "$CONFIG_DIR" checkout -q -- lazy-lock.json 2>/dev/null || true
        if [ -n "$(git -C "$CONFIG_DIR" status --porcelain --untracked-files=no)" ]; then
            warn "local changes in $CONFIG_DIR; backing it up and re-cloning"
            fetch_config
            backup "$CONFIG_DIR"
            place_config
        elif ! git -C "$CONFIG_DIR" pull -q --ff-only origin "$BRANCH"; then
            warn "local history diverged from origin/$BRANCH; backing it up and re-cloning"
            fetch_config
            backup "$CONFIG_DIR"
            place_config
        fi
    else
        fetch_config
        if [ -e "$CONFIG_DIR" ] || [ -L "$CONFIG_DIR" ]; then
            # Plugins and state from another config would conflict with this one.
            backup "$CONFIG_DIR"
            backup "$DATA_HOME/nvim"
            backup "$STATE_HOME/nvim"
            backup "$CACHE_HOME/nvim"
        fi
        place_config
    fi
    ok "config at $CONFIG_DIR ($(git -C "$CONFIG_DIR" rev-parse --short HEAD))"
}

# lua/plugins/theme.lua follows the Omarchy theme. Off Omarchy that symlink
# dangles and breaks the plugin import, so pin a fallback colorscheme instead.
fix_theme() {
    local theme="$CONFIG_DIR/lua/plugins/theme.lua"
    [ -L "$theme" ] || return 0
    [ -e "$theme" ] && { ok "Omarchy theme link resolves"; return; }
    warn "Omarchy theme not found; using tokyonight for lua/plugins/theme.lua"
    rm "$theme"
    cat > "$theme" <<'EOF'
-- Fallback written by install.sh: the Omarchy theme link did not resolve.
return {
  { "LazyVim/LazyVim", opts = { colorscheme = "tokyonight" } },
}
EOF
    git -C "$CONFIG_DIR" update-index --skip-worktree lua/plugins/theme.lua
}

# lua/plugins/epitech-dump-arch.lua loads a plugin from the data dir. Install
# just that plugin from epitech-dump-arch (the full installer also sets up the
# school toolchain; run it separately if you want that).
install_epitech_plugin() {
    local dest="$DATA_HOME/nvim/epitech-upgrade/nvim/epitech.nvim"
    if [ -e "$dest" ] && [ ! -f "$dest/.epitech-dump-arch" ]; then
        warn "$dest exists and is not managed by epitech-dump-arch; leaving it alone"
        return
    fi
    log "Installing the epitech.nvim plugin"
    git clone -q --depth 1 "$EPITECH_URL" "$TMP/epitech"
    local src="$TMP/epitech/nvim/epitech.nvim"
    [ -f "$src/lua/epitech/init.lua" ] || die "epitech.nvim not found in $EPITECH_URL"
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    ok "epitech.nvim at $dest"
    if ! have clang-format || ! clang-format --dump-config \
        --style="file:$dest/epitech.clang-format" >/dev/null 2>&1; then
        warn "clang-format 21+ not available; <leader>cf on C files will fail"
    fi
}

sync_plugins() {
    log "Installing locked plugins (headless)"
    if nvim --headless "+Lazy! restore" +qa; then
        ok "plugins installed"
    else
        warn "plugin install reported errors; open nvim and run :Lazy restore, then :checkhealth"
    fi
}

# --- Main -------------------------------------------------------------------

if [ "$INSTALL_DEPS" -eq 1 ]; then install_packages; fi
have git || die "git is required"
have curl || die "curl is required"
ensure_nvim
ensure_tree_sitter
install_config
fix_theme
install_epitech_plugin
sync_plugins
log "Done. Start nvim."
