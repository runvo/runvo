# System Architecture — runvo

## Overview

runvo is a mobile command center for AI coding agents — a single Bash script that manages projects, tmux sessions, and AI CLI interactions with phone-optimized UX.

## System Diagram

```
┌─────────────┐     SSH      ┌──────────┐    bash    ┌──────────┐    tmux    ┌──────────┐
│   iPhone    │ ──────────── │   Mac    │ ────────── │ runvo.sh │ ────────── │  tmux    │
│  (Termius)  │  Tailscale   │  (sshd)  │            │          │            │ session  │
└─────────────┘              └──────────┘            └──────────┘            └────┬─────┘
                                                                                  │
                                                                          ┌───────┴───────┐
                                                                          │   AI CLI      │
                                                                          │ (claude/aider)│
                                                                          └───────────────┘
```

## Components

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| Main script | `runvo.sh` | 982 | All CLI logic |
| Installer | `install.sh` | 150 | Clone + shell integration |
| Dev setup | `setup.sh` | 44 | Local dev helper |
| Prompts | `prompts/*.txt` | 4 files | Shipped prompt templates |
| User data | `~/.runvo/` | runtime | Config, projects, custom prompts, history |

## Subsystems

### 1. Project Registry

```
~/.runvo/projects.conf
┌────────────────────────────────────────────────┐
│ name | path | description                      │
│ my-app | ~/Projects/my-app | Side project      │
└────────────────────────────────────────────────┘
         ↓ load_projects()
┌────────────────────────────────┐
│ PROJECT_NAMES[]                │
│ PROJECT_PATHS[]                │  parallel arrays
│ PROJECT_DESCS[]                │
└────────────────────────────────┘
```

Operations: load, add, remove, list, edit via `$EDITOR`

### 2. Prompt System

```
Shipped: $SCRIPT_DIR/prompts/*.txt     Custom: ~/.runvo/prompts/custom/*.txt
         ↓                                      ↓
         └──────── load_prompts() ──────────────┘
                        ↓
              Custom overrides shipped (by filename)
                        ↓
              PROMPT_NAMES[] + PROMPT_FILES[]
```

4 shipped: `review`, `fix-lint`, `test`, `status`

### 3. Session Management (tmux)

```
run_agent_interactive()
         ↓
   Session exists? ──── No ──→ tmux new-session → attach
         │
        Yes
         ↓
   Smart resume menu:
     1) Continue (attach existing)
     2) New chat (kill + restart)
     3) Resume last (claude --continue)
```

- Sessions named `runvo-{project_name}`
- Persist across SSH disconnects
- Listed via `runvo sessions`

### 4. Agent Abstraction

```
Config: RUNVO_AGENT + RUNVO_AGENT_PROMPT_FLAG
         ↓
   detect_agent() / get_agent_flag()
         ↓
   claude → "-p"
   aider  → "--message"
   custom → user-configured flag
         ↓
   Two modes:
     Interactive: tmux session → $AGENT
     Prompt:      $AGENT $FLAG "$prompt_text"
```

### 5. TUI Layer

```
$HAS_GUM check
    ├── true  → gum filter/confirm/input
    └── false → plain bash read/echo (numbers-only)
```

- Pink/rose color theme
- 2-space indent on all output
- Status indicators: ✓ ✗ ⚠ ● ○ ▸ ⬆

### 6. Self-Update

```
check_update()
    ↓
git fetch origin master
    ↓
Compare HEAD vs origin/master (rev-list --count)
    ↓
Behind? → confirm → git pull --ff-only
```

Background fetch on startup (`check_update_silent`)

### 7. SSH Auto-Launch

Marker block injected into `.zshrc`/`.bashrc`:
```bash
# >>> runvo-ssh-auto >>>
if [[ -n "$SSH_CONNECTION" ]] && command -v runvo &>/dev/null; then
    runvo
fi
# <<< runvo-ssh-auto <<<
```

Toggle on/off from main menu or `runvo ssh-auto`

### 8. History

```
log_history() → ~/.runvo/history.log
    Format: timestamp|project|action|status
    Capped: 100 entries (tail truncation)
    Display: last 20 (show_history)
```

## Execution Flow

```
runvo [args]
    ↓
load_prompts()
    ↓
Parse CLI args:
    ├── help/setup/add/remove/list/config/prompts/prompt/sessions/history/update/version
    │   → Execute command, exit
    ├── <number> [action]
    │   → load_projects() → run_quick()
    └── (no args)
        → check_deps() → load_projects() → show_banner()
        → check_update_silent() → main_menu()
        → User picks project → run_agent_interactive()
```

## Installation Architecture

```
Method 1: brew tap runvo/runvo && brew install runvo
Method 2: curl ... | bash → install.sh
Method 3: git clone + source setup.sh

All result in:
    ~/.runvo/runvo.sh  (main script)
    Shell function: runvo() { bash ~/.runvo/runvo.sh "$@" }
```

## Security

- No network calls except git operations (update check)
- Prompt name sanitization (reject `/` and `..`)
- User config outside repo (git-ignored)
- No secrets stored in config files
- AGPL-3.0 license (source must remain open)

## Limitations

- macOS-focused (brew references, zshrc priority)
- Single-user design (no multi-user/team features)
- No encryption for stored paths/config
- Sequential project loading (no caching)
- Bash 4+ required (arrays)
