#!/bin/bash

# runvo — Mobile command center for AI coding agents
# Run AI coding CLIs (Claude Code, Aider, etc.) from your phone via SSH
# Copyright (c) 2025 Tran Thai Hoang <admi@tranthaihoang.com>
# https://github.com/runvo/runvo

RUNVO_VERSION="1.0.3"

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

# --- UI helpers ---
print_sep() { echo -e "    ${C_DIM}────────────────────────────────────────${C_RESET}"; }
print_header() { echo ""; echo -e "    ${C_ROSE}$1${C_RESET}"; print_sep; echo ""; }
validate_prompt_name() {
  [[ "$1" == */* || "$1" == *..* ]] && { echo -e "  ${C_RED}Invalid name.${C_RESET}"; return 1; }
}

# Validate project name (alphanumeric, hyphens, underscores, dots)
validate_project_name() {
  [[ "$1" =~ ^[a-zA-Z0-9_.-]+$ ]] || {
    echo -e "  ${C_RED}Invalid name. Use letters, numbers, hyphens, underscores only.${C_RESET}"
    return 1
  }
}

# Escape string for use in grep -E regex
quote_regex() { sed 's/[.[\*^$()+?{|\\]/\\&/g' <<< "$1"; }

# Portable reverse lines (tac not available on macOS by default)
reverse_lines() {
  if command -v tac &>/dev/null; then tac; else tail -r; fi
}

# Resolve target (number or name) to project name
# Usage: resolve_target <target> → sets RESOLVED_NAME
resolve_target() {
  local target="$1"
  if [[ "$target" =~ ^[0-9]+$ ]]; then
    load_projects || { echo -e "  ${C_DIM}No projects.${C_RESET}" >&2; return 1; }
    if (( target < 1 || target > ${#PROJECT_NAMES[@]} )); then
      echo -e "  ${C_RED}Invalid project number (1-${#PROJECT_NAMES[@]})${C_RESET}" >&2
      return 1
    fi
    RESOLVED_NAME="${PROJECT_NAMES[$((target - 1))]}"
  else
    RESOLVED_NAME="$target"
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

# Resolve prompt flag for any agent name
agent_flag_for() {
  case "$1" in
    claude) echo "-p" ;;
    aider)  echo "--message" ;;
    *)      echo "$RUNVO_AGENT_PROMPT_FLAG" ;;
  esac
}

get_agent_flag() { agent_flag_for "$RUNVO_AGENT"; }

# Resume command for agent (only claude supports --continue)
agent_resume_cmd() {
  case "$1" in
    claude) echo "$1 --continue" ;;
    *)      echo "$1" ;;
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
# Format: name | path | description | agent (optional)
load_projects() {
  PROJECT_NAMES=()
  PROJECT_PATHS=()
  PROJECT_DESCS=()
  PROJECT_AGENTS=()

  [[ -f "$PROJECTS_FILE" ]] || return 1

  while IFS='|' read -r name path desc agent; do
    [[ "$name" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$name" ]] && continue
    name=$(echo "$name" | xargs)
    path=$(echo "$path" | xargs)
    desc=$(echo "$desc" | xargs)
    agent=$(echo "$agent" | xargs)
    path="${path/#\~/$HOME}"
    PROJECT_NAMES+=("$name")
    PROJECT_PATHS+=("$path")
    PROJECT_DESCS+=("$desc")
    PROJECT_AGENTS+=("$agent")
  done < "$PROJECTS_FILE"

  [[ ${#PROJECT_NAMES[@]} -eq 0 ]] && return 1
  return 0
}

# Get agent for a specific project (falls back to global)
get_project_agent() {
  local idx=$1
  local agent="${PROJECT_AGENTS[$idx]}"
  [[ -n "$agent" ]] && echo "$agent" || echo "$RUNVO_AGENT"
}

get_project_agent_flag() { agent_flag_for "$(get_project_agent "$1")"; }

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
  tail -n $LOG_MAX "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
}

show_history() {
  if [[ ! -f "$LOG_FILE" || ! -s "$LOG_FILE" ]]; then
    echo -e "  ${C_DIM}No history yet.${C_RESET}"
    return
  fi
  print_header "HISTORY"
  reverse_lines < "$LOG_FILE" | head -20 | while IFS='|' read -r ts project action status; do
    local short_ts="${ts##* }"  # HH:MM:SS
    short_ts="${short_ts%:*}"    # HH:MM
    local icon="${C_GREEN}●${C_RESET}"
    local suffix=""
    if [[ "$status" != "ok" ]]; then
      icon="${C_RED}●${C_RESET}"
      suffix=" ${C_DIM}($status)${C_RESET}"
    fi
    printf "   %b ${C_DIM}%s${C_RESET}  ${C_WHITE}%-16s${C_RESET} ${C_CYAN}%s${C_RESET}%b\n" \
      "$icon" "$short_ts" "$project" "$action" "$suffix"
  done
  echo ""
}

# --- Run AI agent with prompt (non-interactive, single shot) ---
run_agent_prompt() {
  local project_path=$1 project_name=$2 prompt_text=$3 action_name=$4 proj_idx=${5:-}

  if [[ ! -d "$project_path" ]]; then
    echo -e "  ${C_RED}✗ Path not found: $project_path${C_RESET}"
    log_history "$project_name" "$action_name" "path-missing"
    return 1
  fi

  # Use per-project agent if available
  local agent flag
  if [[ -n "$proj_idx" ]]; then
    agent=$(get_project_agent "$proj_idx")
    flag=$(get_project_agent_flag "$proj_idx")
  else
    agent="$RUNVO_AGENT"
    flag=$(get_agent_flag)
  fi

  print_header "RUN"
  printf "    ${C_DIM}Project${C_RESET}  ${C_WHITE}%s${C_RESET}\n" "$project_name"
  printf "    ${C_DIM}Action${C_RESET}   ${C_CYAN}%s${C_RESET}\n" "$action_name"
  printf "    ${C_DIM}Agent${C_RESET}    ${C_DIM}%s${C_RESET}\n" "$agent"
  echo ""

  local -a agent_cmd=("$agent" "$flag" "$prompt_text")
  (cd "$project_path" && "${agent_cmd[@]}")
  local exit_code=$?

  echo ""
  print_sep
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
  local project_path=$1 project_name=$2 proj_idx=${3:-}
  local session_name="runvo-${project_name}"

  # Per-project agent
  local agent="$RUNVO_AGENT"
  [[ -n "$proj_idx" ]] && agent=$(get_project_agent "$proj_idx")

  if [[ ! -d "$project_path" ]]; then
    echo -e "  ${C_RED}✗ Path not found: $project_path${C_RESET}"
    return 1
  fi

  if tmux has-session -t "$session_name" 2>/dev/null; then
    # Session exists — ask: attach or new
    print_header "SESSION: $project_name"
    echo -e "   ${C_WHITE}1${C_RESET}  Continue session"
    echo -e "   ${C_WHITE}2${C_RESET}  New chat"
    echo -e "   ${C_WHITE}3${C_RESET}  Resume last chat"
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
        tmux send-keys -l -t "$session_name" "$agent"
        tmux send-keys -t "$session_name" Enter
        tmux attach-session -t "$session_name"
        ;;
      3)
        tmux kill-session -t "$session_name" 2>/dev/null
        tmux new-session -d -s "$session_name" -c "$project_path"
        local resume_cmd
        resume_cmd=$(agent_resume_cmd "$agent")
        tmux send-keys -l -t "$session_name" "$resume_cmd"
        tmux send-keys -t "$session_name" Enter
        tmux attach-session -t "$session_name"
        ;;
      *)
        return
        ;;
    esac
  else
    tmux new-session -d -s "$session_name" -c "$project_path"
    tmux send-keys -l -t "$session_name" "$agent"
    tmux send-keys -t "$session_name" Enter
    tmux attach-session -t "$session_name"
  fi

  log_history "$project_name" "interactive" "ok"
}

# --- List active tmux sessions ---
show_sessions() {
  print_header "SESSIONS"
  local sessions
  sessions=$(tmux list-sessions 2>/dev/null | grep "^runvo-")
  if [[ -z "$sessions" ]]; then
    echo -e "   ${C_DIM}No active sessions${C_RESET}"
  else
    local idx=1
    while read -r line; do
      local display="${line#runvo-}"
      printf "   ${C_WHITE}%d${C_RESET}  %s\n" "$idx" "$display"
      ((idx++))
    done <<< "$sessions"
    echo ""
    echo -e "   ${C_DIM}Attach: tmux attach -t runvo-<name>${C_RESET}"
  fi
  echo ""
}

# --- Display project list ---
display_projects() {
  if [[ ${#PROJECT_NAMES[@]} -eq 0 ]]; then
    echo -e "   ${C_DIM}No projects configured. Run: runvo setup${C_RESET}"
    return
  fi
  # Dynamic column width (cap 10-20)
  local max_len=10
  for name in "${PROJECT_NAMES[@]}"; do
    (( ${#name} > max_len )) && max_len=${#name}
  done
  (( max_len > 20 )) && max_len=20
  local col_w=$((max_len + 2))

  for i in "${!PROJECT_NAMES[@]}"; do
    local num=$((i + 1))
    local name="${PROJECT_NAMES[$i]}"
    local desc="${PROJECT_DESCS[$i]}"
    local indicator="  "
    if tmux has-session -t "runvo-${name}" 2>/dev/null; then
      indicator="${C_GREEN}●${C_RESET} "
    fi
    printf "   ${C_WHITE}%d${C_RESET}  %b${C_CYAN}%-${col_w}s${C_RESET} ${C_DIM}%s${C_RESET}\n" \
      "$num" "$indicator" "$name" "$desc"
  done
}

# --- Display actions menu ---
display_actions() {
  echo -e "    ${C_ROSE}ACTIONS${C_RESET}"
  print_sep
  echo ""
  local idx=1
  for name in "${PROMPT_NAMES[@]}"; do
    printf "   ${C_WHITE}%d${C_RESET}  ${C_CYAN}%s${C_RESET}\n" "$idx" "$name"
    ((idx++))
  done
  echo ""
  echo -e "   ${C_WHITE}c${C_RESET}  Custom prompt"
  echo -e "   ${C_WHITE}i${C_RESET}  Interactive session"
  echo -e "   ${C_WHITE}b${C_RESET}  ${C_DIM}Back${C_RESET}"
}

# --- Banner ---
show_banner() {
  local ver bw=40
  ver=$(get_version)

  # Dynamic padding for version-dependent line
  local dc=$((bw - 14 - ${#ver}))
  local dashes_top=$(printf '%*s' "$dc" '' | tr ' ' '─')
  local dashes_btm=$(printf '%*s' "$((bw - 26))" '' | tr ' ' '─')
  local sp2=$(printf '%*s' "$((bw - 37))" '')
  local sp3=$(printf '%*s' "$((bw - 20))" '')

  echo ""
  echo -e "    ${C_DIM}╭─── ${C_PINK}runvo${C_DIM} ${dashes_top} ${C_RESET}v${ver}${C_DIM} ─╮${C_RESET}"
  echo -e "    ${C_DIM}│${C_RESET}  Mobile command center for AI agents${sp2}${C_DIM}│${C_RESET}"
  echo -e "    ${C_DIM}│${C_RESET}  ${C_ROSE}by Tran Thai Hoang${C_RESET}${sp3}${C_DIM}│${C_RESET}"
  echo -e "    ${C_DIM}╰── github.com/runvo/runvo ${dashes_btm}╯${C_RESET}"
}

# --- Version & Update ---

# Detect install method: "brew" or "git"
is_brew_install() {
  [[ "$SCRIPT_DIR" == */Cellar/* || "$SCRIPT_DIR" == */homebrew/* ]] && return 0
  # Not a git repo = likely brew
  [[ ! -d "$SCRIPT_DIR/.git" ]] && return 0
  return 1
}

get_version() {
  if is_brew_install; then
    # Brew install — use version constant
    echo "$RUNVO_VERSION"
  else
    # Git install — tag + commit hash
    local tag commit
    tag=$(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null)
    commit=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "dev")
    if [[ -n "$tag" ]]; then
      echo "$tag-$commit"
    else
      echo "$RUNVO_VERSION-$commit"
    fi
  fi
}

check_update() {
  echo -e "  ${C_DIM}Checking for updates...${C_RESET}"
  if is_brew_install; then
    # Brew install — check via brew outdated
    brew update --quiet 2>/dev/null
    if brew outdated --quiet 2>/dev/null | grep -q "^runvo$"; then
      local latest
      latest=$(brew info runvo 2>/dev/null | head -1 | awk '{print $3}')
      echo -e "  ${C_YELLOW}⬆ Update available${C_RESET} ${C_DIM}($RUNVO_VERSION → ${latest:-newer})${C_RESET}"
      return 0
    else
      echo -e "  ${C_GREEN}✓ Up to date${C_RESET} ${C_DIM}($(get_version))${C_RESET}"
      return 1
    fi
  else
    # Git install — check via git
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
  fi
}

do_update() {
  echo -e "  ${C_DIM}Updating...${C_RESET}"
  # Clear version cache to prevent re-triggering on exec
  rm -f "$RUNVO_DIR/.latest_version"
  if is_brew_install; then
    # Brew install — upgrade via brew
    brew update --quiet 2>/dev/null
    if brew upgrade runvo 2>/dev/null; then
      echo -e "  ${C_GREEN}✓ Updated${C_RESET}"
      return 0
    else
      echo -e "  ${C_YELLOW}Already up to date.${C_RESET}"
      return 1
    fi
  else
    # Git install — pull latest
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
  fi
}

check_update_silent() {
  if is_brew_install; then
    # Brew install — lightweight GitHub API check (background result from last run)
    local cache_file="$RUNVO_DIR/.latest_version"
    if [[ -f "$cache_file" ]]; then
      local latest
      latest=$(cat "$cache_file" 2>/dev/null)
      if [[ -n "$latest" && "$latest" != "$RUNVO_VERSION" ]]; then
        echo -e "${C_YELLOW}    ⬆ Update available ($RUNVO_VERSION → $latest)${C_RESET}"
        if confirm_action "Update now?"; then
          do_update && exec bash "${BASH_SOURCE[0]}" "$@"
        fi
      fi
    fi
    # Background fetch latest version for next run
    (curl -sfL "https://api.github.com/repos/runvo/runvo/releases/latest" 2>/dev/null \
      | grep -o '"tag_name":[^,]*' | head -1 | cut -d'"' -f4 | sed 's/^v//' \
      > "$cache_file" 2>/dev/null) &
  else
    # Git install — check via last fetch
    local behind
    behind=$(git -C "$SCRIPT_DIR" rev-list --count HEAD..origin/master 2>/dev/null || echo "0")
    if [[ "$behind" -gt 0 ]]; then
      echo -e "${C_YELLOW}    ⬆ Update available ($behind new)${C_RESET}"
      if confirm_action "Update now?"; then
        do_update && exec bash "${BASH_SOURCE[0]}" "$@"
      fi
    fi
    git -C "$SCRIPT_DIR" fetch origin master --quiet 2>/dev/null &
  fi
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
  print_sep
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
    validate_project_name "$name" || return 1
    path="${path/#\~/$HOME}"

    local ename
    ename=$(quote_regex "$name")
    if grep -qE "^[[:space:]]*${ename}[[:space:]]*\|" "$PROJECTS_FILE" 2>/dev/null; then
      echo -e "  ${C_RED}Project '$name' already exists.${C_RESET}"
      return 1
    fi
    [[ ! -d "$path" ]] && echo -e "  ${C_YELLOW}⚠ Path doesn't exist: $path${C_RESET}"

    echo "$name | $path | $desc" >> "$PROJECTS_FILE"
    echo -e "  ${C_GREEN}✓ Added: $name → $path${C_RESET}"
  else
    # Interactive mode — use read directly (gum duplicates in tmux)
    echo -e "  ${C_DIM}Register an existing project folder${C_RESET}"
    echo ""
    local name path desc

    read -rp "  Project path: " path
    [[ -z "$path" ]] && return
    path="${path/#\~/$HOME}"

    if [[ ! -d "$path" ]]; then
      echo -e "  ${C_YELLOW}⚠ Path doesn't exist: $path${C_RESET}"
      confirm_action "Add anyway?" || return
    fi

    # Default name from folder name
    local default_name
    default_name=$(basename "$path")
    read -rp "  Name [$default_name]: " name
    [[ -z "$name" ]] && name="$default_name"

    local ename
    ename=$(quote_regex "$name")
    if grep -qE "^[[:space:]]*${ename}[[:space:]]*\|" "$PROJECTS_FILE" 2>/dev/null; then
      echo -e "  ${C_RED}Project '$name' already exists.${C_RESET}"
      return 1
    fi

    read -rp "  Description (optional): " desc

    echo "$name | $path | $desc" >> "$PROJECTS_FILE"
    echo -e "  ${C_GREEN}✓ Added: $name → $path${C_RESET}"
  fi
}

cmd_new_project() {
  ensure_projects_header

  # Get name from arg or prompt (read directly — gum duplicates in tmux)
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    read -rp "  Project name: " name
    [[ -z "$name" ]] && return
  fi

  # Validate name
  validate_project_name "$name" || return 1

  # Check not already registered
  local ename
  ename=$(quote_regex "$name")
  if grep -qE "^[[:space:]]*${ename}[[:space:]]*\|" "$PROJECTS_FILE" 2>/dev/null; then
    echo -e "  ${C_RED}Project '$name' already registered.${C_RESET}"
    return 1
  fi

  # Get description
  local desc
  read -rp "  Description (optional): " desc

  # Ask path
  local default_path="$HOME/Projects/$name"
  local path
  read -rp "  Path [$default_path]: " path
  [[ -z "$path" ]] && path="$default_path"
  path="${path/#\~/$HOME}"

  # Handle directory
  if [[ -d "$path" ]]; then
    echo -e "  ${C_YELLOW}Directory exists: $path${C_RESET}"
    confirm_action "Use existing directory?" || return
  else
    mkdir -p "$path"
    echo -e "  ${C_GREEN}✓ Created: $path${C_RESET}"
  fi

  # Init git if needed
  if [[ ! -d "$path/.git" ]]; then
    git init --quiet "$path"
    echo -e "  ${C_GREEN}✓ Initialized git repo${C_RESET}"
  fi

  # Register in projects.conf
  echo "$name | $path | $desc" >> "$PROJECTS_FILE"
  echo -e "  ${C_GREEN}✓ Registered: $name${C_RESET}"
  echo ""

  # Offer AI session
  if confirm_action "Open AI session now?"; then
    load_projects 2>/dev/null
    run_agent_interactive "$path" "$name"
  fi
}

cmd_remove_project() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo -e "  ${C_RED}Usage: runvo remove <name>${C_RESET}"
    return 1
  fi

  local ename
  ename=$(quote_regex "$name")
  if ! grep -qE "^[[:space:]]*${ename}[[:space:]]*\|" "$PROJECTS_FILE" 2>/dev/null; then
    echo -e "  ${C_RED}Project '$name' not found.${C_RESET}"
    return 1
  fi

  if confirm_action "Remove project '$name'?"; then
    local line_num
    line_num=$(grep -nE "^[[:space:]]*${ename}[[:space:]]*\|" "$PROJECTS_FILE" | head -1 | cut -d: -f1)
    if [[ -n "$line_num" ]]; then
      sed -i.bak "${line_num}d" "$PROJECTS_FILE"
      rm -f "$PROJECTS_FILE.bak"
    fi
    echo -e "  ${C_GREEN}✓ Removed: $name${C_RESET}"
  fi
}

# --- Prompt Management ---
cmd_list_prompts() {
  print_header "PROMPTS"
  echo -e "    ${C_WHITE}Shipped${C_RESET}"
  for f in "$PROMPTS_DIR_SHIPPED"/*.txt; do
    [[ -f "$f" ]] || continue
    echo -e "      ${C_CYAN}$(basename "$f" .txt)${C_RESET}"
  done
  echo ""
  echo -e "    ${C_WHITE}Custom${C_RESET}"
  local has_custom=false
  for f in "$PROMPTS_DIR_USER"/*.txt; do
    [[ -f "$f" ]] || continue
    echo -e "      ${C_GREEN}$(basename "$f" .txt)${C_RESET}"
    has_custom=true
  done
  $has_custom || echo -e "      ${C_DIM}(none)${C_RESET}"
  echo ""
}

cmd_add_prompt() {
  local name="$1"
  if [[ -z "$name" ]]; then
    name=$(input_text "Prompt name" "my-prompt")
    [[ -z "$name" ]] && return
  fi
  validate_prompt_name "$name" || return 1

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
  validate_prompt_name "$name" || return 1

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
  validate_prompt_name "$name" || return 1

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
  echo -e "    ${C_ROSE}PROJECTS${C_RESET}"
  display_projects
  echo ""
  echo -e "    ${C_DIM}- - - - - - - - - - - - - - - - - - - -${C_RESET}"
  echo ""
  echo -e "   ${C_WHITE}+${C_RESET}  Add existing"
  echo -e "   ${C_WHITE}n${C_RESET}  Create new"
  echo -e "   ${C_WHITE}-${C_RESET}  Remove project"
  # Show ssh-auto status
  local auto_status="${C_DIM}off${C_RESET}"
  local rc_file="$HOME/.zshrc"
  [[ "$SHELL" == *bash ]] && rc_file="$HOME/.bashrc"
  grep -qF "$AUTOSTART_MARKER_START" "$rc_file" 2>/dev/null && auto_status="${C_GREEN}on${C_RESET}"
  echo -e "   ${C_WHITE}s${C_RESET}  SSH auto-launch  ${auto_status}"
  echo ""

  local proj_choice
  read -rp "  # " proj_choice

  # Quit: empty or q
  [[ -z "$proj_choice" || "$proj_choice" == "q" ]] && return 1

  # Add existing project
  if [[ "$proj_choice" == "+" ]]; then
    cmd_add_project
    return 0
  fi

  # Remove project
  if [[ "$proj_choice" == "-" ]]; then
    echo ""
    echo -e "  ${C_DIM}Which project to remove?${C_RESET}"
    display_projects
    echo ""
    local rm_choice
    read -rp "  # " rm_choice
    if [[ "$rm_choice" =~ ^[0-9]+$ ]] && (( rm_choice >= 1 && rm_choice <= ${#PROJECT_NAMES[@]} )); then
      cmd_remove_project "${PROJECT_NAMES[$((rm_choice - 1))]}"
    fi
    return 0
  fi

  # Create new project
  if [[ "$proj_choice" == "n" || "$proj_choice" == "N" ]]; then
    cmd_new_project
    return 0
  fi

  # SSH auto-launch toggle
  if [[ "$proj_choice" == "s" || "$proj_choice" == "S" ]]; then
    cmd_ssh_auto
    return 0
  fi

  if [[ ! "$proj_choice" =~ ^[0-9]+$ ]] || (( proj_choice < 1 || proj_choice > ${#PROJECT_NAMES[@]} )); then
    echo -e "  ${C_RED}Invalid${C_RESET}"
    return 0
  fi

  local proj_idx=$((proj_choice - 1))
  local proj_name="${PROJECT_NAMES[$proj_idx]}"
  local proj_path="${PROJECT_PATHS[$proj_idx]}"

  run_agent_interactive "$proj_path" "$proj_name" "$proj_idx"
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
      run_agent_prompt "$proj_path" "$proj_name" "$custom_prompt" "custom" "$proj_idx"
      wait_key
      ;;
    i|I)
      run_agent_interactive "$proj_path" "$proj_name" "$proj_idx"
      ;;
    *)
      if [[ "$action_choice" =~ ^[0-9]+$ ]] && (( action_choice >= 1 && action_choice <= ${#PROMPT_NAMES[@]} )); then
        local action_idx=$((action_choice - 1))
        local action_name="${PROMPT_NAMES[$action_idx]}"
        local prompt_text
        prompt_text=$(cat "${PROMPT_FILES[$action_idx]}")
        echo ""
        run_agent_prompt "$proj_path" "$proj_name" "$prompt_text" "$action_name" "$proj_idx"
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
    run_agent_prompt "$proj_path" "$proj_name" "$2" "custom" "$proj_idx"
  elif [[ "$1" == "i" ]]; then
    run_agent_interactive "$proj_path" "$proj_name" "$proj_idx"
  elif [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= ${#PROMPT_NAMES[@]} )); then
    local action_idx=$(($1 - 1))
    local action_name="${PROMPT_NAMES[$action_idx]}"
    local prompt_text
    prompt_text=$(cat "${PROMPT_FILES[$action_idx]}")
    run_agent_prompt "$proj_path" "$proj_name" "$prompt_text" "$action_name" "$proj_idx"
  elif [[ -z "$1" ]]; then
    run_agent_interactive "$proj_path" "$proj_name" "$proj_idx"
  else
    echo -e "${C_RED}  Unknown action: $1${C_RESET}"
    echo -e "${C_DIM}  Usage: runvo <project#> [action#|c \"prompt\"|i]${C_RESET}"
    exit 1
  fi
}

# --- Show help ---
show_help() {
  echo ""
  echo -e "    ${C_ROSE}RUNVO${C_RESET} ${C_DIM}— Mobile command center for AI coding agents${C_RESET}"
  print_sep
  echo ""
  echo -e "    ${C_ROSE}USAGE${C_RESET}"
  echo -e "    ${C_CYAN}runvo${C_RESET}                       Interactive menu"
  echo -e "    ${C_CYAN}runvo${C_RESET} ${C_WHITE}<n>${C_RESET}                  Open project #n"
  echo -e "    ${C_CYAN}runvo${C_RESET} ${C_WHITE}<n> <a>${C_RESET}              Run action #a on project #n"
  echo -e "    ${C_CYAN}runvo${C_RESET} ${C_WHITE}<n>${C_RESET} c ${C_DIM}\"prompt\"${C_RESET}      Custom prompt"
  echo -e "    ${C_CYAN}runvo${C_RESET} ${C_WHITE}<n>${C_RESET} i                Interactive session"
  echo ""
  echo -e "    ${C_ROSE}COMMANDS${C_RESET}"
  echo -e "    ${C_CYAN}runvo setup${C_RESET}                 Setup wizard"
  echo -e "    ${C_CYAN}runvo new${C_RESET} ${C_DIM}[name]${C_RESET}            Create new project"
  echo -e "    ${C_CYAN}runvo add${C_RESET} ${C_DIM}[name path desc]${C_RESET}  Register existing project"
  echo -e "    ${C_CYAN}runvo clone${C_RESET} ${C_WHITE}<url>${C_RESET} ${C_DIM}[name]${C_RESET}   Clone repo & register"
  echo -e "    ${C_CYAN}runvo edit${C_RESET} ${C_DIM}[n|name]${C_RESET}          Open project in editor"
  echo -e "    ${C_CYAN}runvo remove${C_RESET} ${C_WHITE}<name>${C_RESET}         Remove project"
  echo -e "    ${C_CYAN}runvo list${C_RESET}                  List projects"
  echo -e "    ${C_CYAN}runvo status${C_RESET}                Git status dashboard"
  echo -e "    ${C_CYAN}runvo config${C_RESET}                Edit projects.conf"
  echo -e "    ${C_CYAN}runvo prompts${C_RESET}               List prompts"
  echo -e "    ${C_CYAN}runvo prompt add${C_RESET} ${C_WHITE}<name>${C_RESET}     Add custom prompt"
  echo -e "    ${C_CYAN}runvo prompt edit${C_RESET} ${C_WHITE}<name>${C_RESET}    Edit prompt"
  echo -e "    ${C_CYAN}runvo prompt rm${C_RESET} ${C_WHITE}<name>${C_RESET}      Remove custom prompt"
  echo -e "    ${C_CYAN}runvo send${C_RESET} ${C_WHITE}<n>${C_RESET} ${C_DIM}\"msg\"${C_RESET}        Send prompt to session"
  echo -e "    ${C_CYAN}runvo peek${C_RESET} ${C_DIM}[n]${C_RESET}               View session output"
  echo -e "    ${C_CYAN}runvo attach${C_RESET} ${C_DIM}[name|n]${C_RESET}        Attach to session"
  echo -e "    ${C_CYAN}runvo sessions${C_RESET}              Active tmux sessions"
  echo -e "    ${C_CYAN}runvo kill${C_RESET} ${C_DIM}[name|all]${C_RESET}        Kill session(s)"
  echo -e "    ${C_CYAN}runvo history${C_RESET}               Recent history"
  echo -e "    ${C_CYAN}runvo ssh-auto${C_RESET}              Toggle SSH auto-launch"
  echo -e "    ${C_CYAN}runvo doctor${C_RESET}                Check system health"
  echo -e "    ${C_CYAN}runvo update${C_RESET}                Check & install updates"
  echo -e "    ${C_CYAN}runvo version${C_RESET}               Show version"
  echo ""
  echo -e "    ${C_ROSE}PROJECTS${C_RESET}"
  display_projects
  echo ""
  echo -e "    ${C_ROSE}ACTIONS${C_RESET}"
  local idx=1
  for name in "${PROMPT_NAMES[@]}"; do
    printf "    ${C_WHITE}%d${C_RESET}  %s\n" "$idx" "$name"
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

# --- Status Dashboard ---
cmd_status() {
  load_projects 2>/dev/null
  if [[ ${#PROJECT_NAMES[@]} -eq 0 ]]; then
    echo -e "  ${C_DIM}No projects. Run: runvo setup${C_RESET}"
    return
  fi

  print_header "STATUS"

  for i in "${!PROJECT_NAMES[@]}"; do
    local name="${PROJECT_NAMES[$i]}"
    local path="${PROJECT_PATHS[$i]}"

    # Session indicator
    local sess=" "
    tmux has-session -t "runvo-${name}" 2>/dev/null && sess="${C_GREEN}●${C_RESET}"

    if [[ ! -d "$path" ]]; then
      printf "   %b ${C_CYAN}%-16s${C_RESET} ${C_RED}path missing${C_RESET}\n" "$sess" "$name"
      continue
    fi

    if [[ ! -d "$path/.git" ]]; then
      printf "   %b ${C_CYAN}%-16s${C_RESET} ${C_DIM}not a git repo${C_RESET}\n" "$sess" "$name"
      continue
    fi

    # Git info
    local branch changes ahead behind status_parts=()
    branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "?")
    changes=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    ahead=$(git -C "$path" rev-list --count @{upstream}..HEAD 2>/dev/null || echo "0")
    behind=$(git -C "$path" rev-list --count HEAD..@{upstream} 2>/dev/null || echo "0")

    [[ "$changes" -gt 0 ]] && status_parts+=("${C_YELLOW}${changes} changed${C_RESET}")
    [[ "$ahead" -gt 0 ]] && status_parts+=("${C_GREEN}↑${ahead}${C_RESET}")
    [[ "$behind" -gt 0 ]] && status_parts+=("${C_RED}↓${behind}${C_RESET}")
    [[ ${#status_parts[@]} -eq 0 ]] && status_parts+=("${C_GREEN}clean${C_RESET}")

    local status_str
    status_str=$(IFS=' '; echo "${status_parts[*]}")
    printf "   %b ${C_CYAN}%-16s${C_RESET} ${C_DIM}%-12s${C_RESET} %b\n" \
      "$sess" "$name" "$branch" "$status_str"
  done
  echo ""
}

# --- Kill Sessions ---
cmd_kill() {
  local target="$1"

  if [[ "$target" == "all" ]]; then
    local sessions
    sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^runvo-")
    if [[ -z "$sessions" ]]; then
      echo -e "  ${C_DIM}No active runvo sessions${C_RESET}"
      return
    fi
    local count=0
    while read -r sess; do
      tmux kill-session -t "$sess" 2>/dev/null && ((count++))
    done <<< "$sessions"
    echo -e "  ${C_GREEN}✓ Killed $count session(s)${C_RESET}"
    return
  fi

  if [[ -n "$target" ]]; then
    local session_name="runvo-${target}"
    if tmux has-session -t "$session_name" 2>/dev/null; then
      tmux kill-session -t "$session_name"
      echo -e "  ${C_GREEN}✓ Killed: $target${C_RESET}"
    else
      echo -e "  ${C_RED}No session: $target${C_RESET}"
    fi
    return
  fi

  # Interactive: list and pick
  local sessions
  sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^runvo-")
  if [[ -z "$sessions" ]]; then
    echo -e "  ${C_DIM}No active runvo sessions${C_RESET}"
    return
  fi

  print_header "KILL SESSION"
  local names=()
  local idx=1
  while read -r sess; do
    local display="${sess#runvo-}"
    names+=("$display")
    printf "   ${C_WHITE}%d${C_RESET}  %s\n" "$idx" "$display"
    ((idx++))
  done <<< "$sessions"
  echo ""
  echo -e "   ${C_WHITE}a${C_RESET}  Kill all"
  echo ""

  local choice
  read -rp "  # " choice

  if [[ "$choice" == "a" ]]; then
    cmd_kill all
  elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#names[@]} )); then
    cmd_kill "${names[$((choice - 1))]}"
  fi
}

# --- Clone & Register ---
cmd_clone() {
  local url="$1" name="$2"

  if [[ -z "$url" ]]; then
    echo -e "  ${C_RED}Usage: runvo clone <git-url> [name]${C_RESET}"
    return 1
  fi

  # Derive name from URL if not given
  if [[ -z "$name" ]]; then
    name=$(basename "$url" .git)
  fi

  local target_dir="$HOME/Projects/$name"
  read -rp "  Path [$target_dir]: " custom_path
  [[ -n "$custom_path" ]] && target_dir="${custom_path/#\~/$HOME}"

  if [[ -d "$target_dir" ]]; then
    echo -e "  ${C_YELLOW}Directory exists: $target_dir${C_RESET}"
    confirm_action "Use existing?" || return
  else
    echo -e "  ${C_DIM}Cloning...${C_RESET}"
    if ! git clone "$url" "$target_dir"; then
      echo -e "  ${C_RED}✗ Clone failed${C_RESET}"
      return 1
    fi
    echo -e "  ${C_GREEN}✓ Cloned${C_RESET}"
  fi

  # Register
  ensure_projects_header
  local ename
  ename=$(quote_regex "$name")
  if grep -qE "^[[:space:]]*${ename}[[:space:]]*\|" "$PROJECTS_FILE" 2>/dev/null; then
    echo -e "  ${C_YELLOW}Project '$name' already registered${C_RESET}"
  else
    local desc
    read -rp "  Description (optional): " desc
    echo "$name | $target_dir | $desc" >> "$PROJECTS_FILE"
    echo -e "  ${C_GREEN}✓ Registered: $name${C_RESET}"
  fi

  # Offer session
  if confirm_action "Open AI session now?"; then
    load_projects 2>/dev/null
    run_agent_interactive "$target_dir" "$name"
  fi
}

# --- Doctor: System Diagnostics ---
cmd_doctor() {
  print_header "DOCTOR"

  local issues=0

  # Check core deps
  for dep in tmux git; do
    if command -v "$dep" &>/dev/null; then
      local ver
      ver=$("$dep" -V 2>/dev/null || "$dep" --version 2>/dev/null | head -1)
      echo -e "  ${C_GREEN}✓${C_RESET} $dep  ${C_DIM}$ver${C_RESET}"
    else
      echo -e "  ${C_RED}✗${C_RESET} $dep  ${C_RED}not installed${C_RESET}"
      ((issues++))
    fi
  done

  # Check AI agent
  if [[ -n "$RUNVO_AGENT" ]] && command -v "$RUNVO_AGENT" &>/dev/null; then
    local agent_ver
    agent_ver=$("$RUNVO_AGENT" --version 2>/dev/null | head -1 || echo "installed")
    echo -e "  ${C_GREEN}✓${C_RESET} $RUNVO_AGENT  ${C_DIM}$agent_ver${C_RESET}"
  else
    echo -e "  ${C_YELLOW}△${C_RESET} AI agent  ${C_YELLOW}none detected${C_RESET}"
    ((issues++))
  fi

  # Optional deps
  for dep in gum tailscale; do
    if command -v "$dep" &>/dev/null; then
      echo -e "  ${C_GREEN}✓${C_RESET} $dep  ${C_DIM}(optional)${C_RESET}"
    else
      echo -e "  ${C_DIM}○${C_RESET} $dep  ${C_DIM}not installed (optional)${C_RESET}"
    fi
  done

  echo ""

  # Check config
  echo -e "  ${C_WHITE}Config${C_RESET}"
  if [[ -f "$CONFIG_FILE" ]]; then
    echo -e "  ${C_GREEN}✓${C_RESET} config  ${C_DIM}$CONFIG_FILE${C_RESET}"
  else
    echo -e "  ${C_DIM}○${C_RESET} config  ${C_DIM}not created yet${C_RESET}"
  fi

  if [[ -f "$PROJECTS_FILE" ]]; then
    local proj_count
    proj_count=$(grep -cvE '^[[:space:]]*#|^$' "$PROJECTS_FILE" 2>/dev/null || echo "0")
    echo -e "  ${C_GREEN}✓${C_RESET} projects  ${C_DIM}$proj_count registered${C_RESET}"
  else
    echo -e "  ${C_DIM}○${C_RESET} projects  ${C_DIM}none${C_RESET}"
  fi

  # Check project paths
  load_projects 2>/dev/null
  local bad_paths=0
  for i in "${!PROJECT_NAMES[@]}"; do
    if [[ ! -d "${PROJECT_PATHS[$i]}" ]]; then
      echo -e "  ${C_RED}✗${C_RESET} ${PROJECT_NAMES[$i]}  ${C_RED}path missing: ${PROJECT_PATHS[$i]}${C_RESET}"
      ((bad_paths++))
      ((issues++))
    fi
  done

  # Custom prompts count
  local custom_count=0
  for f in "$PROMPTS_DIR_USER"/*.txt; do
    [[ -f "$f" ]] && ((custom_count++))
  done
  echo -e "  ${C_GREEN}✓${C_RESET} prompts  ${C_DIM}${#PROMPT_NAMES[@]} total ($custom_count custom)${C_RESET}"

  # Active sessions
  local sess_count
  sess_count=$(tmux list-sessions 2>/dev/null | grep -c "^runvo-" || echo "0")
  echo -e "  ${C_GREEN}✓${C_RESET} sessions  ${C_DIM}$sess_count active${C_RESET}"

  # Install method
  local method="git"
  is_brew_install && method="brew"
  echo -e "  ${C_GREEN}✓${C_RESET} install  ${C_DIM}$method ($(get_version))${C_RESET}"

  echo ""
  if [[ $issues -eq 0 ]]; then
    echo -e "  ${C_GREEN}All good!${C_RESET}"
  else
    echo -e "  ${C_YELLOW}$issues issue(s) found${C_RESET}"
  fi
  echo ""
}

# --- Send: dispatch message to running session ---
cmd_send() {
  local proj_num="$1" message="$2"

  if [[ -z "$proj_num" || -z "$message" ]]; then
    echo -e "  ${C_RED}Usage: runvo send <project#> \"message\"${C_RESET}"
    return 1
  fi

  load_projects || { echo -e "  ${C_DIM}No projects.${C_RESET}"; return 1; }

  if [[ ! "$proj_num" =~ ^[0-9]+$ ]] || (( proj_num < 1 || proj_num > ${#PROJECT_NAMES[@]} )); then
    echo -e "  ${C_RED}Invalid project number (1-${#PROJECT_NAMES[@]})${C_RESET}"
    return 1
  fi

  local proj_idx=$((proj_num - 1))
  local proj_name="${PROJECT_NAMES[$proj_idx]}"
  local proj_path="${PROJECT_PATHS[$proj_idx]}"
  local session_name="runvo-${proj_name}"

  # Start session if not running
  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    if [[ ! -d "$proj_path" ]]; then
      echo -e "  ${C_RED}✗ Path not found: $proj_path${C_RESET}"
      return 1
    fi
    local agent
    agent=$(get_project_agent "$proj_idx")
    tmux new-session -d -s "$session_name" -c "$proj_path"
    tmux send-keys -l -t "$session_name" "$agent"
    tmux send-keys -t "$session_name" Enter
    echo -e "  ${C_DIM}Started new session for $proj_name${C_RESET}"
    sleep 2  # Brief wait for agent to initialize
  fi

  # Send the message
  # -l = literal text (prevents control-sequence injection)
  tmux send-keys -l -t "$session_name" "$message"
  tmux send-keys -t "$session_name" Enter
  echo -e "  ${C_GREEN}✓ Sent to $proj_name${C_RESET} ${C_DIM}\"$message\"${C_RESET}"
  log_history "$proj_name" "send" "ok"
}

# --- Peek: view session output without attaching ---
cmd_peek() {
  local target="$1" lines="${2:-30}"

  # Resolve numeric target to project name
  if [[ -n "$target" ]]; then
    resolve_target "$target" || return 1
    target="$RESOLVED_NAME"
  fi

  # If no target, show all sessions' last line
  if [[ -z "$target" ]]; then
    local sessions
    sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^runvo-")
    if [[ -z "$sessions" ]]; then
      echo -e "  ${C_DIM}No active sessions${C_RESET}"
      return
    fi
    print_header "PEEK"
    while read -r sess; do
      local name="${sess#runvo-}"
      local last_line
      last_line=$(tmux capture-pane -t "$sess" -p 2>/dev/null | grep -v '^$' | tail -1)
      printf "   ${C_GREEN}●${C_RESET} ${C_CYAN}%-16s${C_RESET} ${C_DIM}%s${C_RESET}\n" "$name" "${last_line:0:50}"
    done <<< "$sessions"
    echo ""
    return
  fi

  local session_name="runvo-${target}"
  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    echo -e "  ${C_RED}No active session: $target${C_RESET}"
    return 1
  fi

  print_header "PEEK: $target"
  tmux capture-pane -t "$session_name" -p 2>/dev/null | tail -"$lines"
  echo ""
  print_sep
  echo -e "    ${C_DIM}Attach: runvo attach $target${C_RESET}"
  echo ""
}

# --- Attach: quick attach to a session ---
cmd_attach() {
  local target="$1"

  # Resolve numeric target to project name
  if [[ -n "$target" ]]; then
    resolve_target "$target" || return 1
    target="$RESOLVED_NAME"
  fi

  # No target — interactive pick from active sessions
  if [[ -z "$target" ]]; then
    local sessions
    sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^runvo-")
    if [[ -z "$sessions" ]]; then
      echo -e "  ${C_DIM}No active sessions${C_RESET}"
      return
    fi
    print_header "ATTACH"
    echo ""
    local names=()
    local idx=1
    while read -r sess; do
      local display="${sess#runvo-}"
      names+=("$display")
      printf "   ${C_WHITE}%d${C_RESET}  %s\n" "$idx" "$display"
      ((idx++))
    done <<< "$sessions"
    echo ""
    local choice
    read -rp "  # " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#names[@]} )); then
      target="${names[$((choice - 1))]}"
    else
      return
    fi
  fi

  local session_name="runvo-${target}"
  if tmux has-session -t "$session_name" 2>/dev/null; then
    tmux attach-session -t "$session_name"
  else
    echo -e "  ${C_RED}No active session: $target${C_RESET}"
  fi
}

# --- Edit: open project in editor ---
cmd_edit_project() {
  local target="$1"

  load_projects || { echo -e "  ${C_DIM}No projects.${C_RESET}"; return 1; }

  if [[ -z "$target" ]]; then
    # Interactive pick
    echo ""
    display_projects
    echo ""
    local choice
    read -rp "  # " choice
    [[ -z "$choice" ]] && return
    target="$choice"
  fi

  resolve_target "$target" || return 1
  local name="$RESOLVED_NAME"

  # Find project index
  local idx=-1
  for i in "${!PROJECT_NAMES[@]}"; do
    [[ "${PROJECT_NAMES[$i]}" == "$name" ]] && { idx=$i; break; }
  done
  [[ $idx -lt 0 ]] && { echo -e "  ${C_RED}Project '$name' not found${C_RESET}"; return 1; }

  local proj_path="${PROJECT_PATHS[$idx]}"
  if [[ ! -d "$proj_path" ]]; then
    echo -e "  ${C_RED}✗ Path not found: $proj_path${C_RESET}"
    return 1
  fi

  # Open in best available editor
  if command -v code &>/dev/null; then
    code "$proj_path"
  elif command -v cursor &>/dev/null; then
    cursor "$proj_path"
  elif command -v subl &>/dev/null; then
    subl "$proj_path"
  else
    cd "$proj_path" && "${EDITOR:-vi}" .
  fi
  echo -e "  ${C_GREEN}✓ Opened: $name${C_RESET}"
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
    new)
      shift
      cmd_new_project "$@"
      exit $?
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
    status)
      cmd_status
      exit 0
      ;;
    kill)
      shift
      cmd_kill "$@"
      exit 0
      ;;
    clone)
      shift
      cmd_clone "$@"
      exit $?
      ;;
    edit)
      shift
      cmd_edit_project "$@"
      exit $?
      ;;
    doctor)
      cmd_doctor
      exit 0
      ;;
    send)
      shift
      cmd_send "$@"
      exit $?
      ;;
    peek)
      shift
      cmd_peek "$@"
      exit 0
      ;;
    attach)
      shift
      cmd_attach "$@"
      exit 0
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
      install_type="git"
      is_brew_install && install_type="brew"
      echo -e "  ${C_WHITE}runvo${C_RESET} $(get_version) ${C_DIM}($install_type)${C_RESET}"
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
while true; do
  main_menu || break
  load_projects 2>/dev/null
done
