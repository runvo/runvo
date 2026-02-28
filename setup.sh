#!/bin/zsh

# Setup 'runvo' command — Run: source setup.sh (for local dev)

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
MAIN_SCRIPT="$SCRIPT_DIR/runvo.sh"

chmod +x "$MAIN_SCRIPT" 2>/dev/null

MARKER_START="# >>> runvo >>>"
MARKER_END="# <<< runvo <<<"

BLOCK="$MARKER_START
runvo() {
    bash \"$MAIN_SCRIPT\" \"\$@\"
}
$MARKER_END"

# Remove old block then write new — idempotent
if grep -q "$MARKER_START" ~/.zshrc 2>/dev/null; then
    sed -i.bak "/$MARKER_START/,/$MARKER_END/d" ~/.zshrc
    rm -f ~/.zshrc.bak
fi

echo "" >> ~/.zshrc
echo "$BLOCK" >> ~/.zshrc

eval "$BLOCK"

P="\033[38;5;218m"
D="\033[38;5;243m"
C="\033[36m"
R="\033[0m"

echo ""
echo -e "${P}▸ RUNVO ${D}── Ready${R}"
echo ""
echo -e "  ${C}runvo${R}          ${D}Interactive menu${R}"
echo -e "  ${C}runvo 1${R}        ${D}Open project #1 (tmux)${R}"
echo -e "  ${C}runvo 1 2${R}      ${D}Run action #2 on project #1${R}"
echo -e "  ${C}runvo 1 c \"..\"${R} ${D}Custom prompt on #1${R}"
echo -e "  ${C}runvo setup${R}    ${D}Setup wizard${R}"
echo -e "  ${C}runvo help${R}     ${D}Full help${R}"
echo ""
