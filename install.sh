#!/bin/bash
set -e

# runvo installer — curl -fsSL https://raw.githubusercontent.com/runvo/runvo/master/install.sh | bash

RUNVO_DIR="$HOME/.runvo"
REPO_URL="https://github.com/runvo/runvo.git"

# Colors
P="\033[38;5;218m"
G="\033[32m"
Y="\033[33m"
R="\033[31m"
D="\033[38;5;243m"
W="\033[1;37m"
C="\033[36m"
N="\033[0m"

echo ""
echo -e "${P}    ▸ RUNVO INSTALLER${N}"
echo -e "${D}    ────────────────────────────────────────${N}"
echo ""

# --- Check git ---
if ! command -v git &>/dev/null; then
  echo -e "  ${R}✗ git is required but not installed.${N}"
  echo -e "  ${D}Install: https://git-scm.com${N}"
  exit 1
fi
echo -e "  ${G}✓${N} git"

# --- Install tmux (macOS) ---
if ! command -v tmux &>/dev/null; then
  if command -v brew &>/dev/null; then
    echo -e "  ${D}Installing tmux...${N}"
    brew install tmux
    echo -e "  ${G}✓${N} tmux installed"
  else
    echo -e "  ${Y}⚠ tmux not found. Install it:${N}"
    echo -e "  ${D}  macOS: brew install tmux${N}"
    echo -e "  ${D}  Linux: sudo apt install tmux${N}"
  fi
else
  echo -e "  ${G}✓${N} tmux"
fi

# --- Optional: install gum ---
if ! command -v gum &>/dev/null; then
  if command -v brew &>/dev/null; then
    echo -e "  ${D}Installing gum (optional, for better UI)...${N}"
    brew install gum 2>/dev/null || true
    command -v gum &>/dev/null && echo -e "  ${G}✓${N} gum installed"
  fi
else
  echo -e "  ${G}✓${N} gum"
fi

# --- Clone or update repo ---
if [[ -d "$RUNVO_DIR/.git" ]]; then
  echo -e "  ${D}Updating existing installation...${N}"
  if git -C "$RUNVO_DIR" pull --ff-only origin master --quiet 2>/dev/null; then
    echo -e "  ${G}✓${N} Updated"
  else
    echo -e "  ${Y}⚠ Could not update. Using existing version.${N}"
  fi
else
  if [[ -d "$RUNVO_DIR" ]]; then
    echo -e "  ${Y}⚠ $RUNVO_DIR exists but is not a git repo. Backing up...${N}"
    mv "$RUNVO_DIR" "$RUNVO_DIR.bak.$(date +%s)"
  fi
  echo -e "  ${D}Cloning runvo...${N}"
  git clone --quiet "$REPO_URL" "$RUNVO_DIR"
  echo -e "  ${G}✓${N} Cloned to $RUNVO_DIR"
fi

# --- Create user dirs ---
mkdir -p "$RUNVO_DIR/prompts/custom" 2>/dev/null

chmod +x "$RUNVO_DIR/runvo.sh"

# --- Shell integration ---
MARKER_START="# >>> runvo >>>"
MARKER_END="# <<< runvo <<<"
SHELL_BLOCK="$MARKER_START
runvo() {
    bash \"$RUNVO_DIR/runvo.sh\" \"\\\$@\"
}
$MARKER_END"

inject_shell() {
  local rc_file="$1"
  [[ -f "$rc_file" ]] || return

  # Remove old block if exists
  if grep -q "$MARKER_START" "$rc_file" 2>/dev/null; then
    sed -i.bak "/$MARKER_START/,/$MARKER_END/d" "$rc_file"
    rm -f "$rc_file.bak"
  fi

  echo "" >> "$rc_file"
  echo "$SHELL_BLOCK" >> "$rc_file"
}

# Detect and inject into active shells
if [[ -f "$HOME/.zshrc" ]] || [[ "$SHELL" == */zsh ]]; then
  touch "$HOME/.zshrc"
  inject_shell "$HOME/.zshrc"
  echo -e "  ${G}✓${N} Added to ~/.zshrc"
fi

if [[ -f "$HOME/.bashrc" ]] || [[ "$SHELL" == */bash ]]; then
  touch "$HOME/.bashrc"
  inject_shell "$HOME/.bashrc"
  echo -e "  ${G}✓${N} Added to ~/.bashrc"
fi

# Make available immediately
eval "$SHELL_BLOCK" 2>/dev/null || true

# --- Setup completions for git install ---
if [[ -f "$RUNVO_DIR/completions/runvo.bash" ]]; then
  if [[ -f "$HOME/.bashrc" ]] || [[ "$SHELL" == */bash ]]; then
    grep -qF "completions/runvo.bash" "$HOME/.bashrc" 2>/dev/null || \
      echo "source \"$RUNVO_DIR/completions/runvo.bash\"" >> "$HOME/.bashrc"
  fi
fi
if [[ -f "$RUNVO_DIR/completions/runvo.zsh" ]]; then
  if [[ -f "$HOME/.zshrc" ]] || [[ "$SHELL" == */zsh ]]; then
    grep -qF "completions/runvo.zsh" "$HOME/.zshrc" 2>/dev/null || \
      echo "source \"$RUNVO_DIR/completions/runvo.zsh\"" >> "$HOME/.zshrc"
  fi
fi

# --- Check for AI agent ---
echo ""
if command -v claude &>/dev/null; then
  echo -e "  ${G}✓${N} AI agent: claude"
elif command -v aider &>/dev/null; then
  echo -e "  ${G}✓${N} AI agent: aider"
else
  echo -e "  ${Y}⚠ No AI agent found. Install one:${N}"
  echo -e "  ${C}npm i -g @anthropic-ai/claude-code${N}  ${D}(Claude Code)${N}"
  echo -e "  ${C}pip install aider-chat${N}              ${D}(Aider)${N}"
fi

# --- First-run wizard (interactive only) ---
if [[ -t 0 && "$1" != "--unattended" ]]; then
  if [[ ! -f "$RUNVO_DIR/projects.conf" ]] || ! grep -q "^[^#]" "$RUNVO_DIR/projects.conf" 2>/dev/null; then
    echo ""
    bash "$RUNVO_DIR/runvo.sh" setup
  fi
fi

# --- Done ---
echo ""
echo -e "${P}    ▸ RUNVO${N} ${G}installed!${N}"
echo -e "${D}    ────────────────────────────────────────${N}"
echo ""
echo -e "  ${C}runvo${N}          ${D}Interactive menu${N}"
echo -e "  ${C}runvo setup${N}    ${D}Add projects${N}"
echo -e "  ${C}runvo help${N}     ${D}Full help${N}"
echo ""
echo -e "  ${D}Restart your shell or run: source ~/.zshrc${N}"
echo ""
