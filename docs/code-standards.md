# Code Standards — runvo

Conventions and standards for the runvo Bash CLI project.

## Bash Style

### Shebang & Safety
- `#!/bin/bash` for main scripts (runvo.sh, install.sh)
- `#!/bin/zsh` for zsh-specific helpers (setup.sh)
- `set -e` used in install.sh only (fail-fast for installer)
- Main script intentionally avoids `set -e` for graceful error handling

### Function Naming

snake_case with semantic prefixes:

| Prefix | Purpose | Example |
|--------|---------|---------|
| `cmd_*` | CLI command handler | `cmd_add_project()`, `cmd_remove_project()` |
| `show_*` | Display/output | `show_banner()`, `show_history()`, `show_sessions()` |
| `run_*` | Execution | `run_agent_prompt()`, `run_agent_interactive()`, `run_quick()` |
| `check_*` | Validation | `check_deps()`, `check_update()` |
| `load_*` | Data loading | `load_config()`, `load_projects()`, `load_prompts()` |
| `save_*` | Data persistence | `save_config()` |
| `display_*` | Formatted output | `display_projects()`, `display_actions()` |

### Variables

- **Globals/constants**: `UPPER_SNAKE_CASE` — `RUNVO_VERSION`, `PROJECTS_FILE`, `C_PINK`
- **Local variables**: declared with `local` — `local name`, `local path`
- **Arrays**: parallel arrays — `PROJECT_NAMES=()`, `PROJECT_PATHS=()`, `PROJECT_DESCS=()`

### Syntax Conventions

```bash
# Conditionals: [[ ]] style (not [ ])
[[ "$var" == "value" ]]
[[ -f "$file" ]]
[[ "$input" =~ ^[0-9]+$ ]]

# Command substitution: $() (not backticks)
version=$(git describe --tags)

# Quoting: double for variables, single for literals
echo "$variable"
echo 'literal string'
```

## Color System

### Pink-themed palette

```bash
C_PINK="\033[38;5;218m"    # Primary brand
C_ROSE="\033[38;5;175m"    # Secondary
C_DIM="\033[38;5;243m"     # Dimmed/secondary text
C_WHITE="\033[1;37m"       # Bold text
C_CYAN="\033[36m"          # Information
C_GREEN="\033[32m"         # Success
C_YELLOW="\033[33m"        # Warning
C_RED="\033[31m"           # Error
C_RESET="\033[0m"          # Reset
```

Short vars in install.sh: `P`, `G`, `Y`, `R`, `D`, `W`, `C`, `N`

### Output Formatting

- 2-space indent for all output: `echo "  text"`
- Separator line: `────────────────────────────────────────────` (44 chars)
- Status indicators: `✓` (success), `✗` (failure), `⚠` (warning), `●` (active), `○` (inactive), `▸` (action), `⬆` (update)

## Configuration Formats

### projects.conf (pipe-delimited)
```
# name | path | description
my-app | ~/Projects/my-app | Side project
```

### config (key=value)
```
RUNVO_AGENT=claude
RUNVO_AGENT_PROMPT_FLAG=-p
```

### Prompts (plain text)
- `.txt` files in `prompts/` (shipped) or `~/.runvo/prompts/custom/` (user)
- No preprocessing — content passed directly to AI agent

## CLI Design Patterns

- **Numbers-only navigation** — Phone-friendly, no arrow keys
- **gum with fallback** — `$HAS_GUM` check, plain bash `read`/`echo` fallback
- **Marker-based injection** — `# >>> runvo >>> ... # <<< runvo <<<` for shell rc

## Error Handling

- Exit code checking with `$?`
- Missing dependency warnings with install commands
- Path validation before file operations
- Name sanitization: reject `/` and `..` in prompt names

## Git Conventions

- **Commit format**: `type: description` — feat, fix, docs, refactor, license, chore
- **Branch**: master
- **Examples**: `feat: smart session resume`, `docs: update README`

## File Naming

- **Scripts**: lowercase `.sh` — `runvo.sh`, `install.sh`
- **Prompts**: lowercase `.txt` — `review.txt`, `fix-lint.txt`
- **Config**: no extension — `config`, `projects.conf`
- **Docs**: kebab-case `.md` — `code-standards.md`, `system-architecture.md`
