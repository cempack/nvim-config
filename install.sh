#!/usr/bin/env bash
# Install Neovim, everything this LazyVim configuration uses, and the config
# itself. Safe to re-run: what is already installed is kept if recent enough,
# otherwise upgraded; an existing config is backed up, never silently clobbered.
#
#   bash <(wget -qO- https://raw.githubusercontent.com/cempack/nvim-config/main/install.sh)
#
# Options:
#   --no-deps   skip system package installation (no sudo)
#   --force     back up the existing config and re-clone even if it is this repo
set -euo pipefail

REPO_URL="${NVIM_CONFIG_REPO:-https://github.com/cempack/nvim-config.git}"
BRANCH="${NVIM_CONFIG_BRANCH:-main}"
EPITECH_URL="${EPITECH_DUMP_REPO:-https://github.com/cempack/epitech-dump-arch.git}"
VIM_EPITECH_URL="https://github.com/Epitech/vim-epitech.git"
MIN_NVIM="0.11.2"   # LazyVim
MIN_TS="0.26.1"     # nvim-treesitter (main branch)
MIN_NODE="18.0.0"   # json-lsp, installed by Mason through npm
NODE_LINE="24"      # official Node release line used when Node is missing or too old
MBAKE_VERSION="1.4.6"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
CONFIG_DIR="$CONFIG_HOME/nvim"
EPITECH_PLUGIN="$DATA_HOME/nvim/epitech-upgrade/nvim/epitech.nvim"
LOCAL_BIN="$HOME/.local/bin"
LOCAL_OPT="$HOME/.local/opt"
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
# version_ge A B: A >= B
version_ge() { [ -n "$1" ] && [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Tools downloaded below live in ~/.local/bin; use them for the rest of the run.
mkdir -p "$LOCAL_BIN"
export PATH="$LOCAL_BIN:$PATH"

case "$(uname -m)" in
    x86_64|amd64) ARCH="x86_64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) ARCH="" ;;
esac
OS="$(uname -s)"
GUI=0
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then GUI=1; fi

nvim_ok() {
    have nvim && nvim --clean --headless -u NONE \
        "+lua if vim.fn.has('nvim-$MIN_NVIM') == 0 then vim.cmd('cquit 1') end" +qa \
        >/dev/null 2>&1
}
ts_ok() { have tree-sitter && version_ge "$(tree-sitter --version 2>/dev/null | awk '{print $2}')" "$MIN_TS"; }
node_ok() { have node && have npm && version_ge "$(node --version 2>/dev/null | tr -d v)" "$MIN_NODE"; }
clang_format_ok() {
    have clang-format && clang-format --dump-config \
        --style="file:$EPITECH_PLUGIN/epitech.clang-format" >/dev/null 2>&1
}

# --- System packages --------------------------------------------------------
# Only what is missing (or too old) is installed, so packages you already have
# from elsewhere (AUR builds, version managers, ...) are never replaced.

install_packages() {
    local mgr pkgs=()
    if have pacman; then mgr=pacman
    elif have apt-get; then mgr=apt
    elif have dnf; then mgr=dnf
    elif have zypper; then mgr=zypper
    elif have brew; then mgr=brew
    else
        warn "no supported package manager; install git, curl, unzip, ripgrep, fd and a C compiler yourself"
        return
    fi

    # need CMD PACMAN APT DNF ZYPPER BREW  ("-" = not packaged / not needed there;
    # a CMD starting with "!" is added without checking for the command)
    need() {
        local cmd="$1" pkg
        shift
        case "$mgr" in
            pacman) pkg="$1" ;; apt) pkg="$2" ;; dnf) pkg="$3" ;; zypper) pkg="$4" ;; brew) pkg="$5" ;;
        esac
        [ "$pkg" = "-" ] && return
        case "$cmd" in
            !*) ;;
            *) have "$cmd" && return ;;
        esac
        case " ${pkgs[*]-} " in *" $pkg "*) return ;; esac
        pkgs+=("$pkg")
    }
    need git      git         git             git         git         git
    need curl     curl        curl            curl        curl        curl
    need unzip    unzip       unzip           unzip       unzip       unzip
    need gzip     gzip        gzip            gzip        gzip        gzip
    need xz       xz          xz-utils        xz          xz          xz
    need rg       ripgrep     ripgrep         ripgrep     ripgrep     ripgrep
    have fdfind || need fd fd fd-find fd-find fd fd
    need cc       gcc         build-essential gcc         gcc         -
    need make     make        build-essential make        make        make
    # Clipboard and fonts only matter on a desktop (over SSH the config uses OSC 52).
    if [ "$OS" = Linux ] && [ "$GUI" -eq 1 ]; then
        if [ "${XDG_SESSION_TYPE:-}" = x11 ]; then
            need xclip xclip xclip xclip xclip -
        else
            need wl-copy wl-clipboard wl-clipboard wl-clipboard wl-clipboard -
        fi
        need fc-list fontconfig fontconfig fontconfig fontconfig -
    fi
    # Distro builds that are new enough; the others are handled after this step.
    nvim_ok || need '!nvim' neovim - neovim neovim neovim
    ts_ok || need '!tree-sitter' tree-sitter-cli - tree-sitter-cli - tree-sitter-cli
    if ! node_ok; then
        need node nodejs - nodejs - node
        need npm npm - npm - -
    fi
    need lazygit  lazygit     -               -           -           lazygit
    need uv       uv          -               uv          -           uv
    need clang-format clang     -               -           -           clang-format

    if [ "${#pkgs[@]}" -eq 0 ]; then
        ok "system packages already present"
        return
    fi
    log "Installing system packages: ${pkgs[*]}"
    case "$mgr" in
        pacman) $SUDO pacman -S --needed --noconfirm "${pkgs[@]}" ;;
        apt)
            # No needrestart dialogs; wait for the dpkg lock, which a fresh
            # Ubuntu often holds while unattended-upgrades runs.
            $SUDO env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
                apt-get -o DPkg::Lock::Timeout=600 update -y
            $SUDO env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
                apt-get -o DPkg::Lock::Timeout=600 install -y "${pkgs[@]}"
            ;;
        dnf) $SUDO dnf install -y "${pkgs[@]}" ;;
        zypper) $SUDO zypper --non-interactive install "${pkgs[@]}" ;;
        brew) brew install "${pkgs[@]}" ;;
    esac
    hash -r
}

# --- Tools not (recently enough) packaged by the distro ----------------------

ensure_fd_name() {
    # Debian/Ubuntu name the binary fdfind.
    if ! have fd && have fdfind; then ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"; fi
}

ensure_nvim() {
    if ! nvim_ok; then
        [ "$OS" = Linux ] && [ -n "$ARCH" ] \
            || die "install Neovim >= $MIN_NVIM manually (no prebuilt release for $OS-$(uname -m))"
        log "Installing the latest Neovim release into $LOCAL_OPT/nvim"
        curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$ARCH.tar.gz" \
            -o "$TMP/nvim.tar.gz"
        rm -rf "$LOCAL_OPT/nvim"
        mkdir -p "$LOCAL_OPT/nvim"
        tar -xzf "$TMP/nvim.tar.gz" -C "$LOCAL_OPT/nvim" --strip-components=1
        ln -sf "$LOCAL_OPT/nvim/bin/nvim" "$LOCAL_BIN/nvim"
        hash -r
    fi
    nvim_ok || die "Neovim >= $MIN_NVIM is required but $(command -v nvim || echo nvim) is older, missing or does not run"
    ok "$(nvim --version | head -n1) ($(command -v nvim))"
}

# Prebuilt tree-sitter CLIs need glibc 2.39+ (Ubuntu 24.04+). Older systems get
# it compiled from source with a throwaway Rust toolchain.
ensure_tree_sitter() {
    if ! ts_ok && [ "$OS" = Linux ] && [ -n "$ARCH" ]; then
        local asset="tree-sitter-linux-x64.gz"
        [ "$ARCH" = arm64 ] && asset="tree-sitter-linux-arm64.gz"
        log "Installing the tree-sitter CLI"
        if curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/latest/download/$asset" \
                | gunzip > "$TMP/tree-sitter" \
            && chmod +x "$TMP/tree-sitter" \
            && "$TMP/tree-sitter" --version >/dev/null 2>&1; then
            mv "$TMP/tree-sitter" "$LOCAL_BIN/tree-sitter"
        else
            log "Prebuilt tree-sitter does not run here; building it from source (a few minutes)"
            if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
                    | RUSTUP_HOME="$TMP/rustup" CARGO_HOME="$TMP/cargo" \
                        sh -s -- -y -q --profile minimal --no-modify-path \
                && RUSTUP_HOME="$TMP/rustup" CARGO_HOME="$TMP/cargo" \
                    "$TMP/cargo/bin/cargo" install -q --locked tree-sitter-cli --root "$TMP/ts"; then
                mv "$TMP/ts/bin/tree-sitter" "$LOCAL_BIN/tree-sitter"
            fi
        fi
        hash -r
    fi
    if ts_ok; then
        ok "$(tree-sitter --version)"
    else
        warn "tree-sitter CLI >= $MIN_TS unavailable; treesitter parsers will fail to build"
    fi
}

ensure_node() {
    if ! node_ok && [ "$OS" = Linux ] && [ -n "$ARCH" ]; then
        local arch="x64" file
        [ "$ARCH" = arm64 ] && arch="arm64"
        log "Installing Node.js $NODE_LINE (LTS) into $LOCAL_OPT/node"
        file="$(curl -fsSL "https://nodejs.org/dist/latest-v$NODE_LINE.x/SHASUMS256.txt" \
            | grep -o "node-v[0-9.]*-linux-$arch\.tar\.xz" | head -n1)" || true
        [ -n "$file" ] || die "could not find a Node.js $NODE_LINE release for linux-$arch"
        curl -fsSL "https://nodejs.org/dist/latest-v$NODE_LINE.x/$file" -o "$TMP/node.tar.xz"
        rm -rf "$LOCAL_OPT/node"
        mkdir -p "$LOCAL_OPT/node"
        tar -xJf "$TMP/node.tar.xz" -C "$LOCAL_OPT/node" --strip-components=1
        for bin in node npm npx; do ln -sf "$LOCAL_OPT/node/bin/$bin" "$LOCAL_BIN/$bin"; done
        hash -r
    fi
    if node_ok; then
        ok "node $(node --version), npm $(npm --version)"
    else
        warn "Node.js >= $MIN_NODE with npm unavailable; Mason cannot install json-lsp"
    fi
}

ensure_uv() {
    if ! have uv; then
        log "Installing uv"
        curl -LsSf https://astral.sh/uv/install.sh \
            | env UV_INSTALL_DIR="$LOCAL_BIN" UV_NO_MODIFY_PATH=1 sh >/dev/null
        hash -r
    fi
    have uv || warn "uv unavailable; clang-format 21+ and mbake cannot be installed"
}

ensure_lazygit() {
    if ! have lazygit && [ "$OS" = Linux ] && [ -n "$ARCH" ]; then
        local url
        log "Installing lazygit"
        url="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
            | grep -o "https://[^\"]*_linux_$ARCH\.tar\.gz" | head -n1)" || true
        if [ -n "$url" ] && curl -fsSL "$url" -o "$TMP/lazygit.tar.gz" \
            && tar -xzf "$TMP/lazygit.tar.gz" -C "$TMP" lazygit; then
            install -m 755 "$TMP/lazygit" "$LOCAL_BIN/lazygit"
            hash -r
        fi
    fi
    if have lazygit; then ok "lazygit $(lazygit --version | grep -o 'version=[^,]*' | cut -d= -f2)"
    else warn "lazygit unavailable; <leader>gg will not work"; fi
}

# The Epitech formatter needs clang-format 21+ (distro builds are often older)
# and mbake for Makefiles; both come from PyPI through uv when needed.
ensure_formatters() {
    if ! clang_format_ok && have uv; then
        log "Installing clang-format (21+) with uv"
        uv tool install -q --upgrade clang-format || true
        hash -r
    fi
    if clang_format_ok; then ok "$(clang-format --version | head -n1)"
    else warn "clang-format cannot load the Epitech profile; <leader>cf on C files will fail"; fi

    if ! have mbake && have uv; then
        log "Installing mbake $MBAKE_VERSION with uv"
        uv tool install -q "mbake==$MBAKE_VERSION" || true
        hash -r
    fi
    if have mbake; then ok "mbake installed"; else warn "mbake unavailable; Makefiles will not format"; fi
}

# The icons need a Nerd Font in the terminal.
ensure_nerd_font() {
    [ "$GUI" -eq 1 ] && have fc-list || return 0
    # No grep -q: it would close the pipe early and trip pipefail.
    if fc-list : family | grep -i 'nerd' >/dev/null; then
        ok "Nerd Font present"
        return
    fi
    log "Installing JetBrainsMono Nerd Font"
    local dir="$DATA_HOME/fonts/JetBrainsMonoNerdFont"
    mkdir -p "$dir"
    if curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz \
        | tar -xJf - -C "$dir"; then
        fc-cache -f "$dir" >/dev/null 2>&1 || true
        warn "set your terminal font to 'JetBrainsMono Nerd Font' so icons render"
    else
        warn "Nerd Font download failed; icons will show as boxes"
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

# lua/plugins/epitech-dump-arch.lua loads a plugin from the data dir, and its
# formatter runs the Epitech Vim config. Install just those two pieces (the full
# epitech-dump-arch installer also sets up the school toolchain).
install_epitech() {
    if [ -e "$EPITECH_PLUGIN" ] && [ ! -f "$EPITECH_PLUGIN/.epitech-dump-arch" ]; then
        warn "$EPITECH_PLUGIN exists and is not managed by epitech-dump-arch; leaving it alone"
    else
        log "Installing the epitech.nvim plugin"
        git clone -q --depth 1 "$EPITECH_URL" "$TMP/epitech"
        [ -f "$TMP/epitech/nvim/epitech.nvim/lua/epitech/init.lua" ] \
            || die "epitech.nvim not found in $EPITECH_URL"
        rm -rf "$EPITECH_PLUGIN"
        mkdir -p "$(dirname "$EPITECH_PLUGIN")"
        cp -a "$TMP/epitech/nvim/epitech.nvim" "$EPITECH_PLUGIN"
        ok "epitech.nvim at $EPITECH_PLUGIN"
    fi

    log "Installing the Epitech Vim config"
    git clone -q --depth 1 "$VIM_EPITECH_URL" "$TMP/vim-epitech"
    [ -f "$TMP/vim-epitech/epitech.vim" ] || die "epitech.vim not found in $VIM_EPITECH_URL"
    if ! cmp -s "$TMP/vim-epitech/epitech.vim" "$HOME/.vim/epitech.vim"; then
        backup "$HOME/.vim/epitech.vim"
        mkdir -p "$HOME/.vim"
        cp "$TMP/vim-epitech/epitech.vim" "$HOME/.vim/epitech.vim"
    fi
    ok "epitech.vim at $HOME/.vim/epitech.vim"
}

sync_plugins() {
    log "Installing locked plugins (headless)"
    if nvim --headless "+Lazy! restore" +qa; then
        echo
        ok "plugins installed (Mason installs language servers on the first start)"
    else
        warn "plugin install reported errors; open nvim and run :Lazy restore, then :checkhealth"
    fi
}

# Make ~/.local/bin visible to new shells if it is not already.
ensure_path() {
    case ":$ORIG_PATH:" in *":$LOCAL_BIN:"*) return ;; esac
    local rc line='export PATH="$HOME/.local/bin:$PATH"  # added by nvim-config install.sh'
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ "$rc" = "$HOME/.bashrc" ] || [ -f "$rc" ] || continue
        if ! grep -qF 'added by nvim-config install.sh' "$rc" 2>/dev/null; then
            printf '\n%s\n' "$line" >> "$rc"
            ok "added $LOCAL_BIN to PATH in $rc"
        fi
    done
    warn "open a new terminal before running nvim ($LOCAL_BIN is not on this shell's PATH)"
}

# --- Main -------------------------------------------------------------------

if [ "$INSTALL_DEPS" -eq 1 ]; then install_packages; fi
for cmd in git curl tar; do have "$cmd" || die "$cmd is required"; done
ensure_fd_name
ensure_nvim
ensure_tree_sitter
ensure_node
ensure_uv
ensure_lazygit
install_config
fix_theme
install_epitech
ensure_formatters
ensure_nerd_font
sync_plugins
ensure_path
log "Done. Start nvim."
