#!/usr/bin/env sh

set -eu

REPO_URL="${ZSH_LOG_COPY_REPO_URL:-https://github.com/0601p/zsh-log-copy.git}"
INSTALL_DIR="${ZSH_LOG_COPY_INSTALL_DIR:-$HOME/.zsh-log-copy}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
PLUGIN_FILE="$INSTALL_DIR/zsh-log-copy.plugin.zsh"

if ! command -v git >/dev/null 2>&1; then
  printf '%s\n' "zsh-log-copy: git is required to install" >&2
  exit 1
fi

if [ -d "$INSTALL_DIR/.git" ]; then
  printf '%s\n' "zsh-log-copy: updating $INSTALL_DIR"
  git -C "$INSTALL_DIR" pull --ff-only
elif [ -e "$INSTALL_DIR" ]; then
  printf '%s\n' "zsh-log-copy: $INSTALL_DIR already exists and is not a git repository" >&2
  printf '%s\n' "Set ZSH_LOG_COPY_INSTALL_DIR to another path or move the existing directory." >&2
  exit 1
else
  printf '%s\n' "zsh-log-copy: cloning to $INSTALL_DIR"
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

if [ ! -f "$PLUGIN_FILE" ]; then
  printf '%s\n' "zsh-log-copy: plugin file not found at $PLUGIN_FILE" >&2
  exit 1
fi

mkdir -p "$(dirname "$ZSHRC")"
touch "$ZSHRC"

if grep -F 'zsh-log-copy.plugin.zsh' "$ZSHRC" >/dev/null 2>&1; then
  printf '%s\n' "zsh-log-copy: $ZSHRC already loads zsh-log-copy"
else
  escaped_plugin_file=$(printf '%s' "$PLUGIN_FILE" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\$/\\$/g; s/`/\\`/g')
  {
    printf '\n%s\n' '# zsh-log-copy'
    printf 'source "%s"\n' "$escaped_plugin_file"
  } >> "$ZSHRC"
  printf '%s\n' "zsh-log-copy: added source line to $ZSHRC"
fi

printf '%s\n' "zsh-log-copy: installed"
printf '%s\n' "Restart your shell or run: source \"$ZSHRC\""
