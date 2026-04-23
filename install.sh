#!/usr/bin/env bash
# One-shot installer for cc-configure.
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/tigers1997/ClaudeCodeConfigurator/main/install.sh | bash
# or after cloning:
#   ./install.sh [install-dir]
#
# What it does:
#   1. Clones the repo to ~/.cc-configurator (or $1 if given).
#   2. Symlinks configure.py into ~/.local/bin/cc-configure.
#   3. Ensures ~/.local/bin is on PATH (prints instructions if not).
#
# After install:
#   cd your-project && cc-configure
set -euo pipefail

INSTALL_DIR="${1:-$HOME/.cc-configurator}"
REPO_URL="https://github.com/tigers1997/ClaudeCodeConfigurator.git"
BIN_DIR="$HOME/.local/bin"
BIN_NAME="cc-configure"

echo "==> Installing cc-configure"
echo "    source   : $INSTALL_DIR"
echo "    shortcut : $BIN_DIR/$BIN_NAME"

# 1. Clone or update
if [ -d "$INSTALL_DIR/.git" ]; then
  echo "==> $INSTALL_DIR exists — pulling latest"
  git -C "$INSTALL_DIR" pull --ff-only
elif [ -e "$INSTALL_DIR" ]; then
  echo "ERROR: $INSTALL_DIR exists and is not a git clone. Refusing to overwrite." >&2
  exit 1
else
  echo "==> Cloning $REPO_URL"
  git clone --depth=1 "$REPO_URL" "$INSTALL_DIR"
fi

# 2. Ensure Python 3.8+
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found. Install it first (apt install python3)." >&2
  exit 1
fi
PY_VER=$(python3 -c 'import sys; print(".".join(map(str,sys.version_info[:2])))')
if [ "$(python3 -c 'import sys; print(sys.version_info >= (3,8))')" != "True" ]; then
  echo "ERROR: Python 3.8+ required (found $PY_VER)." >&2
  exit 1
fi

# 3. chmod configure.py + symlink
chmod +x "$INSTALL_DIR/configure.py"
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/configure.py" "$BIN_DIR/$BIN_NAME"
echo "==> Linked $BIN_DIR/$BIN_NAME -> $INSTALL_DIR/configure.py"

# 4. PATH hint
if ! echo ":$PATH:" | grep -q ":$BIN_DIR:"; then
  echo ""
  echo "WARNING: $BIN_DIR is not on your PATH."
  echo "Add this line to your shell config (~/.bashrc, ~/.zshrc):"
  echo ""
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo ""
  echo "Then: source ~/.bashrc  (or restart your shell)"
fi

echo ""
echo "==> Done."
echo ""
echo "Usage:"
echo "    cd your-project"
echo "    cc-configure                   # interactive"
echo "    cc-configure --yes --preset aggressive --modules core,safety,git-workflow,token-efficiency-pro,commands-core"
echo "    cc-configure --help            # full options"
echo ""
echo "To update: re-run this installer, or:"
echo "    git -C $INSTALL_DIR pull"
