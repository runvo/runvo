#!/bin/bash

# runvo — Mobile command center for AI coding agents
# Run AI coding CLIs (Claude Code, Aider, etc.) from your phone via SSH
# https://github.com/runvo/runvo

RUNVO_VERSION="1.0.0"

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNVO_DIR="${RUNVO_DIR:-$HOME/.runvo}"
PROJECTS_FILE="$RUNVO_DIR/projects.conf"
PROMPTS_DIR_SHIPPED="$SCRIPT_DIR/prompts"
PROMPTS_DIR_USER="$RUNVO_DIR/prompts/custom"
CONFIG_FILE="$RUNVO_DIR/config"
LOG_DIR="$RUNVO_DIR"
LOG_FILE="$LOG_DIR/history.log"
LOG_MAX=100

mkdir -p "$RUNVO_DIR" "$PROMPTS_DIR_USER" 2>/dev/null

# --- Colors ---
C_PINK="\033[38;5;218m"
C_ROSE="\033[38;5;175m"
C_DIM="\033[38;5;243m"
C_WHITE="\033[1;37m"
C_CYAN="\033[36m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_RED="\033[31m"
C_RESET="\033[0m"

# --- Load config ---
RUNVO_AGENT="${RUNVO_AGENT:-claude}"
RUNVO_AGENT_PROMPT_FLAG="${RUNVO_AGENT_PROMPT_FLAG:--p}"

load_config() {
  [[ -f "$CONFIG_FILE" ]] || return
  while IFS='=' read -r key val; do
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    key=$(echo "$key" | xargs)
    val=$(echo "$val" | xargs)
    case "$key" in
      RUNVO_AGENT) RUNVO_AGENT="$val" ;;
      RUNVO_AGENT_PROMPT_FLAG) RUNVO_AGENT_PROMPT_FLAG="$val" ;;
    esac
  done < "$CONFIG_FILE"
}

save_config() {
  cat > "$CONFIG_FILE" <<EOF
# runvo config
RUNVO_AGENT=$RUNVO_AGENT
RUNVO_AGENT_PROMPT_FLAG=$RUNVO_AGENT_PROMPT_FLAG
EOF
}

load_config

# --- gum TUI helpers with fallback ---
HAS_GUM=false
command -v gum &>/dev/null && HAS_GUM=true

choose_item() {
  local prompt="$1"
  shift
  local items=("$@")
  if $HAS_GUM; then
    printf '%s\n' "${items[@]}" | gum filter --placeholder "$prompt" --height 12
  else
    echo -e "  ${C_WHITE}$prompt${C_RESET}" >&2
    local i=1
    for item in "${items[@]}"; do
      echo -e "  ${C_WHITE}$i${C_RESET}  $item" >&2
      ((i++))
    done
    echo "" >&2
    local choice
    read -rp "  # " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
      echo "${items[$((choice - 1))]}"
    fi
  fi
}

confirm_action() {
  local prompt="${1:-Continue?}"
  if $HAS_GUM; then
    gum confirm "$prompt"
  else
    local ans
    read -rp "  $prompt [y/N] " ans
    [[ "$ans" =~ ^[yY]$ ]]
  fi
}

input_text() {
  local prompt="${1:-Input}"
  local placeholder="${2:-}"
  if $HAS_GUM; then
    gum input --placeholder "$placeholder" --prompt "$prompt: "
  else
    local val
    read -rp "  $prompt: " val
    echo "$val"
  fi
}

# --- Agent detection ---
detect_agent() {
  if command -v claude &>/dev/null; then
    RUNVO_AGENT="claude"
    RUNVO_AGENT_PROMPT_FLAG="-p"
  elif command -v aider &>/dev/null; then
    RUNVO_AGENT="aider"
    RUNVO_AGENT_PROMPT_FLAG="--message"
  else
    RUNVO_AGENT=""
    RUNVO_AGENT_PROMPT_FLAG=""
  fi
}

get_agent_flag() {
  case "$RUNVO_AGENT" in
    claude) echo "-p" ;;
    aider)  echo "--message" ;;
    *)      echo "$RUNVO_AGENT_PROMPT_FLAG" ;;
  esac
}

# --- Check dependencies ---
check_deps() {
  local missing=()
  command -v tmux &>/dev/null || missing+=("tmux")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${C_RED}  Missing: ${missing[*]}${C_RESET}"
    echo -e "${C_DIM}  brew install ${missing[*]}${C_RESET}"
    return 1
  fi
  if [[ -z "$RUNVO_AGENT" ]] || ! command -v "$RUNVO_AGENT" &>/dev/null; then
    echo -e "${C_YELLOW}  No AI agent found.${C_RESET}"
    echo -e "${C_DIM}  Install one: npm i -g @anthropic-ai/claude-code  or  pip install aider-chat${C_RESET}"
    return 1
  fi
}

# --- Load projects from config ---
load_projects() {
  PROJECT_NAMES=()
  PROJECT_PATHS=()
  PROJECT_DESCS=()

  [[ -f "$PROJECTS_FILE" ]] || return 1

  while IFS='|' read -r name path desc; do
    [[ "$name" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$name" ]] && continue
    name=$(echo "$name" | xargs)
    path=$(echo "$path" | xargs)
    desc=$(echo "$desc" | xargs)
    path="${path/#\~/$HOME}"
    PROJECT_NAMES+=("$name")
    PROJECT_PATHS+=("$path")
    PROJECT_DESCS+=("$desc")
  done < "$PROJECTS_FILE"

  [[ ${#PROJECT_NAMES[@]} -eq 0 ]] && return 1
}

# --- Load prompts (shipped + user custom; user overrides shipped by name) ---
load_prompts() {
  PROMPT_NAMES=()
  PROMPT_FILES=()
  local _seen_names=""

  # User custom first (takes priority)
  for f in "$PROMPTS_DIR_USER"/*.txt; do
    [[ -f "$f" ]] || continue
    local name
    name=$(basename "$f" .txt)
    PROMPT_NAMES+=("$name")
    PROMPT_FILES+=("$f")
    _seen_names="$_seen_names|$name|"
  done

  # Shipped defaults (skip if user has override)
  for f in "$PROMPTS_DIR_SHIPPED"/*.txt; do
    [[ -f "$f" ]] || continue
    local name
    name=$(basename "$f" .txt)
    [[ "$_seen_names" == *"|$name|"* ]] && continue
    PROMPT_NAMES+=("$name")
    PROMPT_FILES+=("$f")
  done
}

# --- History ---
log_history() {
  local project=$1 action=$2 status=$3
  echo "$(date '+%Y-%m-%d %H:%M:%S')|$project|$action|$status" >> "$LOG_FILE"
  if [[ -f "$LOG_FILE" ]]; then
    tail -n $LOG_MAX "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
  fi
}

show_history() {
  if [[ ! -f "$LOG_FILE" || ! -s "$LOG_FILE" ]]; then
    echo -e "  ${C_DIM}No history yet.${C_RESET}"
    return
  fi
  echo -e "  ${C_WHITE}HISTORY${C_RESET} ${C_DIM}(last $LOG_MAX)${C_RESET}"
  echo -e "  ${C_DIM}────────────────────────────────────────────${C_RESET}"
  tac "$LOG_FILE" | head -20 | while IFS='|' read -r ts project action status; do
    if [[ "$status" == "ok" ]]; then
      echo -e "  ${C_GREEN}✓${C_RESET} ${C_DIM}$ts${C_RESET}  $project  ${C_CYAN}$action${C_RESET}"
    else
      echo -e "  ${C_RED}✗${C_RESET} ${C_DIM}$ts${C_RESET}  $project  ${C_CYAN}$action${C_RESET}  ${C_RED}($status)${C_RESET}"
    fi
  done
  echo ""
}

# --- Run AI agent with prompt (non-interactive, single shot) ---
run_agent_prompt() {
  local project_path=$1 project_name=$2 prompt_text=$3 action_name=$4

  if [[ ! -d "$project_path" ]]; then
    echo -e "  ${C_RED}✗ Path not found: $project_path${C_RESET}"
    log_history "$project_name" "$action_name" "path-missing"
    return 1
  fi

  local flag
  flag=$(get_agent_flag)

  echo -e "  ${C_DIM}────────────────────────────────────────────${C_RESET}"
  echo -e "  ${C_PINK}▸ Project:${C_RESET} $project_name"
  echo -e "  ${C_PINK}▸ Action:${C_RESET}  $action_name"
  echo -e "  ${C_PINK}▸ Agent:${C_RESET}   $RUNVO_AGENT"
  echo -e "  ${C_DIM}────────────────────────────────────────────${C_RESET}"
  echo ""

  local -a agent_cmd=("$RUNVO_AGENT" "$flag" "$prompt_text")
  (cd "$project_path" && "${agent_cmd[@]}")
  local exit_code=$?

  echo ""
  echo -e "  ${C_DIM}────────────────────────────────────────────${C_RESET}"
  if [[ $exit_code -eq 0 ]]; then
    echo -e "  ${C_GREEN}✓ Done${C_RESET}"
    log_history "$project_name" "$action_name" "ok"
  else
    echo -e "  ${C_RED}✗ Failed (exit $exit_code)${C_RESET}"
    log_history "$project_name" "$action_name" "exit-$exit_code"
  fi
}

# --- Start interactive AI session in tmux ---
run_agent_interactive() {
  local project_path=$1 project_name=$2
  local session_name="runvo-${project_name}"

  if [[ ! -d "$project_path" ]]; then
    echo -e "  ${C_RED}✗ Path not found: $project_path${C_RESET}"
    return 1
  fi

  if tmux has-session -t "$session_name" 2>/dev/null; then
    # Session exists — ask: attach or new
    echo ""
    echo -e "  ${C_PINK}▸ $project_name${C_RESET} ${C_DIM}— session running${C_RESET}"
    echo ""
    echo -e "  ${C_WHITE} 1${C_RESET}  ${C_GREEN}Continue session${C_RESET} ${C_DIM}(attach)${C_RESET}"
    echo -e "  ${C_WHITE} 2${C_RESET}  ${C_CYAN}New chat${C_RESET} ${C_DIM}(kill old + start fresh)${C_RESET}"
    echo -e "  ${C_WHITE} 3${C_RESET}  ${C_CYAN}Resume last chat${C_RESET} ${C_DIM}(claude --continue)${C_RESET}"
    echo ""
    local choice
    read -rp "  # " choice
    case "$choice" in
      1|"")
        tmux attach-session -t "$session_name"
        ;;
      2)
        tmux kill-session -t "$session_name" 2>/dev/null
        tmux new-session -d -s "$session_name" -c "$project_path"
        tmux send-keys -t "$session_name" "$RUNVO_AGENT" Enter
        tmux attach-session -t "$session_name"
        ;;
      3)
        tmux kill-session -t "$session_name" 2>/dev/null
        tmux new-session -d -s "$session_name" -c "$project_path"
        tmux send-keys -t "$session_name" "$RUNVO_AGENT --continue" Enter
        tmux attach-session -t "$session_name"
        ;;
      *)
        return
        ;;
    esac
  else
    tmux new-session -d -s "$session_name" -c "$project_path"
    tmux send-keys -t "$session_name" "$RUNVO_AGENT" Enter
    tmux attach-session -t "$session_name"
  fi

  log_history "$project_name" "interactive" "ok"
}

# --- List active tmux sessions ---
show_sessions() {
  echo -e "  ${C_WHITE}ACTIVE SESSIONS${C_RESET}"
  echo -e "  ${C_DIM}────────────────────────────────────────────${C_RESET}"
  local sessions
  sessions=$(tmux list-sessions 2>/dev/null | grep "^runvo-")
  if [[ -z "$sessions" ]]; then
    echo -e "  ${C_DIM}No active sessions${C_RESET}"
  else
    local idx=1
    while read -r line; do
      echo -e "  ${C_WHITE}$idx${C_RESET}  $line"
      ((idx++))
    done <<< "$sessions"
    echo ""
    echo -e "  ${C_DIM}Attach: tmux attach -t <name>${C_RESET}"
  fi
  echo ""
}

# --- Display project list ---
display_projects() {
  if [[ ${#PROJECT_NAMES[@]} -eq 0 ]]; then
    echo -e "  ${C_DIM}No projects configured. Run: runvo setup${C_RESET}"
    return
  fi
  for i in "${!PROJECT_NAMES[@]}"; do
    local num=$((i + 1))
    local name="${PROJECT_NAMES[$i]}"
    local desc="${PROJECT_DESCS[$i]}"
    local status=""
    # Show indicator if tmux session is running
    if tmux has-session -t "runvo-${name}" 2>/dev/null; then
      status="${C_GREEN}●${C_RESET} "
    fi
    printf "  ${C_WHITE}%2d${C_RESET}  ${status}${C_CYAN}%-20s${C_RESET} ${C_DIM}%s${C_RESET}\n" \
      "$num" "$name" "$desc"
  done
}

# --- Display actions menu ---
display_actions() {
  echo -e "  ${C_WHITE}Actions:${C_RESET}"
  local idx=1
  for name in "${PROMPT_NAMES[@]}"; do
    printf "  ${C_WHITE}%2d${C_RESET}  ${C_CYAN}%s${C_RESET}\n" "$idx" "$name"
    ((idx++))
  done
  echo -e "  ${C_WHITE} c${C_RESET}  ${C_YELLOW}Custom prompt${C_RESET}"
  echo -e "  ${C_WHITE} i${C_RESET}  ${C_GREEN}Interactive session (tmux)${C_RESET}"
  echo -e "  ${C_WHITE} b${C_RESET}  ${C_DIM}Back${C_RESET}"
}

# --- Banner ---
show_banner() {
  echo ""
  echo -e "${C_PINK}    ▸ RUNVO ${C_DIM}── Mobile command center for AI coding agents ${C_DIM}($(get_version))${C_RESET}"
  echo -e "${C_DIM}    ────────────────────────────────────────${C_RESET}"
}

# --- Version & Update ---
get_version() {
  local tag commit
  tag=$(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null)
  commit=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "dev")
  if [[ -n "$tag" ]]; then
    echo "$tag-$commit"
  else
    echo "$RUNVO_VERSION-$commit"
  fi
}

check_update() {
  echo -e "  ${C_DIM}Checking for updates...${C_RESET}"
  git -C "$SCRIPT_DIR" fetch origin master --quiet 2>/dev/null
  local behind
  behind=$(git -C "$SCRIPT_DIR" rev-list --count HEAD..origin/master 2>/dev/null || echo "0")
  if [[ "$behind" -gt 0 ]]; then
    echo -e "  ${C_YELLOW}⬆ Update available${C_RESET} ${C_DIM}($behind commit(s) behind)${C_RESET}"
    return 0
  else
    echo -e "  ${C_GREEN}✓ Up to date${C_RESET} ${C_DIM}($(get_version))${C_RESET}"
    return 1
  fi
}

do_update() {
  echo -e "  ${C_DIM}Updating...${C_RESET}"
  local old_head
  old_head=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)
  if git -C "$SCRIPT_DIR" pull --ff-only origin master --quiet 2>/dev/null; then
    echo -e "  ${C_GREEN}✓ Updated to $(get_version)${C_RESET}"
    echo ""
    echo -e "  ${C_WHITE}What's new:${C_RESET}"
    git -C "$SCRIPT_DIR" log --format="  ${C_CYAN}•${C_RESET} %s" "$old_head..HEAD" 2>/dev/null
    echo ""
    return 0
  else
    echo -e "  ${C_RED}✗ Update failed (local changes?)${C_RESET}"
    echo -e "  ${C_DIM}Try: cd \"$SCRIPT_DIR\" && git pull${C_RESET}"
    return 1
  fi
}

check_update_silent() {
  local behind
  behind=$(git -C "$SCRIPT_DIR" rev-list --count HEAD..origin/master 2>/dev/null || echo "0")
  if [[ "$behind" -gt 0 ]]; then
    echo -e "${C_YELLOW}    ⬆ Update available ($behind new)${C_RESET}"
    if confirm_action "Update now?"; then
      do_update && exec bash "${BASH_SOURCE[0]}" "$@"
    fi
  fi
  git -C "$SCRIPT_DIR" fetch origin master --quiet 2>/dev/null &
}

# --- Setup Wizard ---
ensure_projects_header() {
  if [[ ! -f "$PROJECTS_FILE" ]]; then
    cat > "$PROJECTS_FILE" <<'CONF'
# runvo — Project Registry
# Format: name | path | description
# Lines starting with # are ignored
CONF
  fi
}

run_setup_wizard() {
  echo ""
  echo -e "${C_PINK}    ▸ RUNVO SETUP${C_RESET}"
  echo -e "${C_DIM}    ────────────────────────────────────────${C_RESET}"
  echo ""

  ensure_projects_header

  if [[ -z "$RUNVO_AGENT" ]] || ! command -v "$RUNVO_AGENT" &>/dev/null; then
    detect_agent
  fi

  if [[ -z "$RUNVO_AGENT" ]]; then
    echo -e "  ${C_YELLOW}No AI agent found.${C_RESET}"
    echo -e "  ${C_DIM}Install one:${C_RESET}"
    echo -e "  ${C_CYAN}npm i -g @anthropic-ai/claude-code${C_RESET}  ${C_DIM}(Claude Code)${C_RESET}"
    echo -e "  ${C_CYAN}pip install aider-chat${C_RESET}              ${C_DIM}(Aider)${C_RESET}"
    echo ""
  else
    echo -e "  ${C_GREEN}✓ Agent: $RUNVO_AGENT${C_RESET}"
    save_config
  fi

  echo -e "  ${C_WHITE}Let's add some projects!${C_RESET}"
  echo ""

  local count=0
  while true; do
    local name path desc

    name=$(input_text "Project name" "my-app")
    [[ -z "$name" ]] && break

    path=$(input_text "Project path" "~/Projects/$name")
    [[ -z "$path" ]] && break
    path="${path/#\~/$HOME}"

    if [[ ! -d "$path" ]]; then
      echo -e "  ${C_YELLOW}⚠ Path doesn't exist: $path${C_RESET}"
      confirm_action "Add anyway?" || continue
    fi

    desc=$(input_text "Description (optional)" "")

    echo "$name | $path | $desc" >> "$PROJECTS_FILE"
    echo -e "  ${C_GREEN}✓ Added: $name${C_RESET}"
    ((count++))
    echo ""

    confirm_action "Add another project?" || break
  done

  echo ""
  if [[ $count -gt 0 ]]; then
    echo -e "  ${C_GREEN}✓ $count project(s) configured.${C_RESET}"
  else
    echo -e "  ${C_DIM}No projects added. Run 'runvo setup' anytime.${C_RESET}"
  fi
  echo -e "  ${C_DIM}Run 'runvo' to start!${C_RESET}"
  echo ""
}

# --- Project Management ---
cmd_add_project() {
  ensure_projects_header

  if [[ -n "$1" && -n "$2" ]]; then
    local name="$1" path="$2" desc="${3:-}"
    path="${path/#\~/$HOME}"

    if grep -qF "$name |" "$PROJECTS_FILE" 2>/dev/null; then
      echo -e "  ${C_RED}Project '$name' already exists.${C_RESET}"
      return 1
    fi
    [[ ! -d "$path" ]] && echo -e "  ${C_YELLOW}⚠ Path doesn't exist: $path${C_RESET}"

    echo "$name | $path | $desc" >> "$PROJECTS_FILE"
    echo -e "  ${C_GREEN}✓ Added: $name → $path${C_RESET}"
  else
    local name path desc
    name=$(input_text "Project name" "my-app")
    [[ -z "$name" ]] && return

    if grep -qF "$name |" "$PROJECTS_FILE" 2>/dev/null; then
      echo -e "  ${C_RED}Project '$name' already exists.${C_RESET}"
      return 1
    fi

    path=$(input_text "Project path" "~/Projects/$name")
    [[ -z "$path" ]] && return
    path="${path/#\~/$HOME}"

    if [[ ! -d "$path" ]]; then
      echo -e "  ${C_YELLOW}⚠ Path doesn't exist: $path${C_RESET}"
      confirm_action "Add anyway?" || return
    fi

    desc=$(input_text "Description (optional)" "")

    echo "$name | $path | $desc" >> "$PROJECTS_FILE"
    echo -e "  ${C_GREEN}✓ Added: $name → $path${C_RESET}"
  fi
}

cmd_remove_project() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo -e "  ${C_RED}Usage: runvo remove <name>${C_RESET}"
    return 1
  fi

  if ! grep -qF "$name |" "$PROJECTS_FILE" 2>/dev/null; then
    echo -e "  ${C_RED}Project '$name' not found.${C_RESET}"
    return 1
  fi

  if confirm_action "Remove project '$name'?"; then
    local line_num
    line_num=$(grep -nF "$name |" "$PROJECTS_FILE" | head -1 | cut -d: -f1)
    if [[ -n "$line_num" ]]; then
      sed -i.bak "${line_num}d" "$PROJECTS_FILE"
      rm -f "$PROJECTS_FILE.bak"
    fi
    echo -e "  ${C_GREEN}✓ Removed: $name${C_RESET}"
  fi
}

# --- Prompt Management ---
cmd_list_prompts() {
  echo -e "  ${C_WHITE}PROMPTS${C_RESET}"
  echo -e "  ${C_DIM}────────────────────────────────────────────${C_RESET}"

  echo -e "  ${C_WHITE}Shipped:${C_RESET}"
  for f in "$PROMPTS_DIR_SHIPPED"/*.txt; do
    [[ -f "$f" ]] || continue
    echo -e "    ${C_CYAN}$(basename "$f" .txt)${C_RESET}"
  done

  echo -e "  ${C_WHITE}Custom:${C_RESET}"
  local has_custom=false
  for f in "$PROMPTS_DIR_USER"/*.txt; do
    [[ -f "$f" ]] || continue
    echo -e "    ${C_GREEN}$(basename "$f" .txt)${C_RESET}"
    has_custom=true
  done
  $has_custom || echo -e "    ${C_DIM}(none)${C_RESET}"
  echo ""
}

cmd_add_prompt() {
  local name="$1"
  if [[ -z "$name" ]]; then
    name=$(input_text "Prompt name" "my-prompt")
    [[ -z "$name" ]] && return
  fi
  [[ "$name" == */* || "$name" == *..* ]] && { echo -e "  ${C_RED}Invalid name.${C_RESET}"; return 1; }

  local file="$PROMPTS_DIR_USER/$name.txt"
  if [[ -f "$file" ]]; then
    echo -e "  ${C_YELLOW}Prompt '$name' exists. Use 'runvo prompt edit $name'.${C_RESET}"
    return 1
  fi

  echo -e "  ${C_DIM}Enter prompt text (Ctrl+D when done):${C_RESET}"
  local content
  content=$(cat)

  if [[ -z "$content" ]]; then
    echo -e "  ${C_RED}Empty prompt, cancelled.${C_RESET}"
    return 1
  fi

  echo "$content" > "$file"
  echo -e "  ${C_GREEN}✓ Saved: $file${C_RESET}"
}

cmd_edit_prompt() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo -e "  ${C_RED}Usage: runvo prompt edit <name>${C_RESET}"
    return 1
  fi
  [[ "$name" == */* || "$name" == *..* ]] && { echo -e "  ${C_RED}Invalid name.${C_RESET}"; return 1; }

  local file="$PROMPTS_DIR_USER/$name.txt"
  if [[ ! -f "$file" ]]; then
    if [[ -f "$PROMPTS_DIR_SHIPPED/$name.txt" ]]; then
      echo -e "  ${C_DIM}Copying shipped prompt to custom for editing...${C_RESET}"
      cp "$PROMPTS_DIR_SHIPPED/$name.txt" "$file"
    else
      echo -e "  ${C_RED}Prompt '$name' not found.${C_RESET}"
      return 1
    fi
  fi

  "${EDITOR:-vi}" "$file"
}

cmd_remove_prompt() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo -e "  ${C_RED}Usage: runvo prompt rm <name>${C_RESET}"
    return 1
  fi
  [[ "$name" == */* || "$name" == *..* ]] && { echo -e "  ${C_RED}Invalid name.${C_RESET}"; return 1; }

  local file="$PROMPTS_DIR_USER/$name.txt"
  if [[ ! -f "$file" ]]; then
    if [[ -f "$PROMPTS_DIR_SHIPPED/$name.txt" ]]; then
      echo -e "  ${C_RED}Cannot delete shipped prompt '$name'. Only custom prompts can be removed.${C_RESET}"
    else
      echo -e "  ${C_RED}Prompt '$name' not found.${C_RESET}"
    fi
    return 1
  fi

  if confirm_action "Delete custom prompt '$name'?"; then
    rm "$file"
    echo -e "  ${C_GREEN}✓ Deleted: $name${C_RESET}"
  fi
}

# --- Main menu (phone-friendly: numbers only, no arrow keys) ---
main_menu() {
  echo ""
  display_projects
  echo ""
  echo -e "  ${C_WHITE} +${C_RESET}  ${C_DIM}Add project${C_RESET}"
  # Show ssh-auto status
  local auto_status="${C_DIM}○ off${C_RESET}"
  local rc_file="$HOME/.zshrc"
  [[ "$SHELL" == *bash ]] && rc_file="$HOME/.bashrc"
  grep -qF "$AUTOSTART_MARKER_START" "$rc_file" 2>/dev/null && auto_status="${C_GREEN}● on${C_RESET}"
  echo -e "  ${C_WHITE} s${C_RESET}  ${C_DIM}SSH auto-launch${C_RESET} ${auto_status}"
  echo ""

  local proj_choice
  read -rp "  # " proj_choice

  [[ -z "$proj_choice" || "$proj_choice" == "q" ]] && return

  # Add project shortcut
  if [[ "$proj_choice" == "+" ]]; then
    cmd_add_project
    return
  fi

  # SSH auto-launch toggle
  if [[ "$proj_choice" == "s" || "$proj_choice" == "S" ]]; then
    cmd_ssh_auto
    return
  fi

  if [[ ! "$proj_choice" =~ ^[0-9]+$ ]] || (( proj_choice < 1 || proj_choice > ${#PROJECT_NAMES[@]} )); then
    echo -e "  ${C_RED}Invalid${C_RESET}"
    return
  fi

  local proj_idx=$((proj_choice - 1))
  local proj_name="${PROJECT_NAMES[$proj_idx]}"
  local proj_path="${PROJECT_PATHS[$proj_idx]}"

  run_agent_interactive "$proj_path" "$proj_name"
}

# --- Run task flow (numbers only, phone-friendly) ---
run_task_flow() {
  echo ""
  display_projects
  echo ""
  read -rp "  Project # " proj_choice

  if [[ ! "$proj_choice" =~ ^[0-9]+$ ]] || (( proj_choice < 1 || proj_choice > ${#PROJECT_NAMES[@]} )); then
    echo -e "  ${C_RED}Invalid${C_RESET}"
    return
  fi

  local proj_idx=$((proj_choice - 1))
  local proj_name="${PROJECT_NAMES[$proj_idx]}"
  local proj_path="${PROJECT_PATHS[$proj_idx]}"

  echo ""
  echo -e "  ${C_PINK}▸ $proj_name${C_RESET} ${C_DIM}($proj_path)${C_RESET}"
  echo ""

  display_actions
  echo ""
  read -rp "  Action # " action_choice

  case "$action_choice" in
    b|B|"") return ;;
    c|C)
      echo ""
      read -rp "  Prompt: " custom_prompt
      [[ -z "$custom_prompt" ]] && return
      echo ""
      run_agent_prompt "$proj_path" "$proj_name" "$custom_prompt" "custom"
      wait_key
      ;;
    i|I)
      run_agent_interactive "$proj_path" "$proj_name"
      ;;
    *)
      if [[ "$action_choice" =~ ^[0-9]+$ ]] && (( action_choice >= 1 && action_choice <= ${#PROMPT_NAMES[@]} )); then
        local action_idx=$((action_choice - 1))
        local action_name="${PROMPT_NAMES[$action_idx]}"
        local prompt_text
        prompt_text=$(cat "${PROMPT_FILES[$action_idx]}")
        echo ""
        run_agent_prompt "$proj_path" "$proj_name" "$prompt_text" "$action_name"
        wait_key
      else
        echo -e "  ${C_RED}Invalid${C_RESET}"
      fi
      ;;
  esac
}

# --- Wait for keypress ---
wait_key() {
  echo ""
  echo -e "  ${C_DIM}Press any key...${C_RESET}"
  read -rsn1
}

# --- Quick mode: runvo <project#> [action#|c "prompt"|i] ---
run_quick() {
  local proj_num=$1
  shift

  if [[ ! "$proj_num" =~ ^[0-9]+$ ]] || (( proj_num < 1 || proj_num > ${#PROJECT_NAMES[@]} )); then
    echo -e "${C_RED}  Invalid project number (1-${#PROJECT_NAMES[@]})${C_RESET}"
    exit 1
  fi

  local proj_idx=$((proj_num - 1))
  local proj_name="${PROJECT_NAMES[$proj_idx]}"
  local proj_path="${PROJECT_PATHS[$proj_idx]}"

  if [[ "$1" == "c" && -n "$2" ]]; then
    run_agent_prompt "$proj_path" "$proj_name" "$2" "custom"
  elif [[ "$1" == "i" ]]; then
    run_agent_interactive "$proj_path" "$proj_name"
  elif [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= ${#PROMPT_NAMES[@]} )); then
    local action_idx=$(($1 - 1))
    local action_name="${PROMPT_NAMES[$action_idx]}"
    local prompt_text
    prompt_text=$(cat "${PROMPT_FILES[$action_idx]}")
    run_agent_prompt "$proj_path" "$proj_name" "$prompt_text" "$action_name"
  elif [[ -z "$1" ]]; then
    run_agent_interactive "$proj_path" "$proj_name"
  else
    echo -e "${C_RED}  Unknown action: $1${C_RESET}"
    echo -e "${C_DIM}  Usage: runvo <project#> [action#|c \"prompt\"|i]${C_RESET}"
    exit 1
  fi
}

# --- Show help ---
show_help() {
  echo ""
  echo -e "  ${C_WHITE}RUNVO${C_RESET} ${C_DIM}— Mobile command center for AI coding agents${C_RESET}"
  echo ""
  echo -e "  ${C_WHITE}USAGE${C_RESET}"
  echo -e "  ${C_CYAN}runvo${C_RESET}                       Interactive menu"
  echo -e "  ${C_CYAN}runvo${C_RESET} ${C_WHITE}<n>${C_RESET}                  Open project #n (tmux)"
  echo -e "  ${C_CYAN}runvo${C_RESET} ${C_WHITE}<n> <a>${C_RESET}              Run action #a on project #n"
  echo -e "  ${C_CYAN}runvo${C_RESET} ${C_WHITE}<n>${C_RESET} c ${C_DIM}\"prompt\"${C_RESET}      Custom prompt on project #n"
  echo -e "  ${C_CYAN}runvo${C_RESET} ${C_WHITE}<n>${C_RESET} i                Interactive session #n"
  echo ""
  echo -e "  ${C_WHITE}COMMANDS${C_RESET}"
  echo -e "  ${C_CYAN}runvo setup${C_RESET}                 First-run setup wizard"
  echo -e "  ${C_CYAN}runvo add${C_RESET} [name path desc]  Add project"
  echo -e "  ${C_CYAN}runvo remove${C_RESET} ${C_WHITE}<name>${C_RESET}         Remove project"
  echo -e "  ${C_CYAN}runvo list${C_RESET}                  List projects"
  echo -e "  ${C_CYAN}runvo config${C_RESET}                Edit projects.conf"
  echo -e "  ${C_CYAN}runvo prompts${C_RESET}               List all prompts"
  echo -e "  ${C_CYAN}runvo prompt add${C_RESET} ${C_WHITE}<name>${C_RESET}     Add custom prompt"
  echo -e "  ${C_CYAN}runvo prompt edit${C_RESET} ${C_WHITE}<name>${C_RESET}    Edit prompt"
  echo -e "  ${C_CYAN}runvo prompt rm${C_RESET} ${C_WHITE}<name>${C_RESET}      Remove custom prompt"
  echo -e "  ${C_CYAN}runvo sessions${C_RESET}              Active tmux sessions"
  echo -e "  ${C_CYAN}runvo history${C_RESET}               Recent history"
  echo -e "  ${C_CYAN}runvo ssh-auto${C_RESET}              Auto-launch on SSH login"
  echo -e "  ${C_CYAN}runvo update${C_RESET}                Check & install updates"
  echo -e "  ${C_CYAN}runvo version${C_RESET}               Show version"
  echo ""
  echo -e "  ${C_WHITE}PROJECTS${C_RESET}"
  display_projects
  echo ""
  echo -e "  ${C_WHITE}ACTIONS${C_RESET}"
  local idx=1
  for name in "${PROMPT_NAMES[@]}"; do
    printf "  ${C_WHITE}%2d${C_RESET}  %s\n" "$idx" "$name"
    ((idx++))
  done
  echo ""
}

# --- SSH Auto-launch ---
AUTOSTART_MARKER_START="# >>> runvo-ssh-auto >>>"
AUTOSTART_MARKER_END="# <<< runvo-ssh-auto <<<"
AUTOSTART_BLOCK='# >>> runvo-ssh-auto >>>
# Auto-launch runvo on SSH login
if [[ -n "$SSH_CONNECTION" ]] && command -v runvo &>/dev/null; then
    runvo
fi
# <<< runvo-ssh-auto <<<'

cmd_ssh_auto() {
  # Detect shell rc file
  local rc_file
  if [[ -n "$ZSH_VERSION" ]] || [[ "$SHELL" == *zsh ]]; then
    rc_file="$HOME/.zshrc"
  else
    rc_file="$HOME/.bashrc"
  fi

  # Check current state
  if grep -qF "$AUTOSTART_MARKER_START" "$rc_file" 2>/dev/null; then
    echo -e "  ${C_GREEN}● SSH auto-launch is ON${C_RESET}"
    echo ""
    echo -e "  ${C_WHITE} 1${C_RESET}  ${C_RED}Turn OFF${C_RESET}"
    echo -e "  ${C_WHITE} 2${C_RESET}  ${C_DIM}Keep ON${C_RESET}"
    echo ""
    local choice
    read -rp "  # " choice
    if [[ "$choice" == "1" ]]; then
      # Remove the block
      sed -i.bak "/$AUTOSTART_MARKER_START/,/$AUTOSTART_MARKER_END/d" "$rc_file"
      rm -f "$rc_file.bak"
      echo -e "  ${C_GREEN}✓ Disabled. Restart shell to apply.${C_RESET}"
    fi
  else
    echo -e "  ${C_DIM}○ SSH auto-launch is OFF${C_RESET}"
    echo ""
    echo -e "  ${C_DIM}When enabled, runvo starts automatically when you SSH in${C_RESET}"
    echo -e "  ${C_DIM}(e.g. from Termius on iPhone). Only triggers on SSH, not local terminal.${C_RESET}"
    echo ""
    echo -e "  ${C_WHITE} 1${C_RESET}  ${C_GREEN}Turn ON${C_RESET}"
    echo -e "  ${C_WHITE} 2${C_RESET}  ${C_DIM}Cancel${C_RESET}"
    echo ""
    local choice
    read -rp "  # " choice
    if [[ "$choice" == "1" ]]; then
      echo "" >> "$rc_file"
      echo "$AUTOSTART_BLOCK" >> "$rc_file"
      echo -e "  ${C_GREEN}✓ Enabled! Next SSH login will auto-launch runvo.${C_RESET}"
    fi
  fi
}

# ===== MAIN =====

load_prompts

# CLI args
if [[ $# -ge 1 ]]; then
  case "$1" in
    help|--help|-h)
      load_projects 2>/dev/null
      show_help
      exit 0
      ;;
    setup)
      run_setup_wizard
      exit 0
      ;;
    add)
      shift
      cmd_add_project "$@"
      exit $?
      ;;
    remove|rm)
      shift
      cmd_remove_project "$@"
      exit $?
      ;;
    list|projects)
      load_projects 2>/dev/null
      display_projects
      echo ""
      exit 0
      ;;
    config)
      ensure_projects_header
      "${EDITOR:-vi}" "$PROJECTS_FILE"
      exit 0
      ;;
    prompts)
      cmd_list_prompts
      exit 0
      ;;
    prompt)
      shift
      case "$1" in
        add)  shift; cmd_add_prompt "$@" ;;
        edit) shift; cmd_edit_prompt "$@" ;;
        rm|remove) shift; cmd_remove_prompt "$@" ;;
        *)    echo -e "  ${C_RED}Usage: runvo prompt [add|edit|rm] <name>${C_RESET}" ;;
      esac
      exit $?
      ;;
    sessions)
      show_sessions
      exit 0
      ;;
    ssh-auto)
      cmd_ssh_auto
      exit 0
      ;;
    history)
      show_history
      exit 0
      ;;
    update)
      check_update && confirm_action "Update now?" && do_update
      exit 0
      ;;
    version|--version|-v)
      echo -e "  ${C_WHITE}runvo${C_RESET} $(get_version)"
      echo -e "  ${C_DIM}Agent: $RUNVO_AGENT${C_RESET}"
      exit 0
      ;;
    *)
      check_deps || exit 1
      load_projects || { echo -e "  ${C_DIM}No projects. Run: runvo setup${C_RESET}"; exit 1; }
      run_quick "$@"
      exit $?
      ;;
  esac
fi

# No args → interactive menu
check_deps || exit 1
load_projects 2>/dev/null
show_banner

if [[ ${#PROJECT_NAMES[@]} -eq 0 ]]; then
  echo -e "  ${C_YELLOW}No projects yet. Let's add one:${C_RESET}"
  echo ""
  cmd_add_project
  load_projects 2>/dev/null
  [[ ${#PROJECT_NAMES[@]} -eq 0 ]] && exit 0
fi

check_update_silent "$@"
main_menu
