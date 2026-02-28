# runvo

Mobile command center for AI coding agents. Run Claude Code, Aider, or any AI CLI from your phone via SSH.

```bash
curl -fsSL https://raw.githubusercontent.com/runvo/runvo/master/install.sh | bash
```

## Features

- **One command** to run AI agents on any project
- **tmux sessions** — persistent, resumable from any device
- **Agent-agnostic** — Claude Code, Aider, or any CLI agent
- **Preset prompts** — review, test, fix-lint, status (+ custom)
- **gum TUI** — beautiful menus with plain-text fallback
- **Auto-update** — stay current with `runvo update`
- **Phone-friendly** — designed for Termius + Tailscale SSH

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/runvo/runvo/master/install.sh | bash
```

Requires: `git`, `tmux`, and an AI CLI (`claude` or `aider`). The installer handles `tmux` and optional `gum` via Homebrew.

## Quick Start

```bash
# 1. Install
curl -fsSL https://raw.githubusercontent.com/runvo/runvo/master/install.sh | bash

# 2. Add a project (or use the setup wizard)
runvo add my-app ~/Projects/my-app "My App"

# 3. Run
runvo              # Interactive menu
runvo 1            # Open project #1 in tmux
runvo 1 1          # Run preset action #1 on project #1
```

## Usage

```bash
# Interactive
runvo                       # Full menu with gum (or plain fallback)

# Quick commands
runvo <n>                   # Open project #n (tmux interactive)
runvo <n> <a>               # Run preset action #a on project #n
runvo <n> c "fix the bug"   # Custom prompt on project #n
runvo <n> i                 # Interactive tmux session

# Project management
runvo setup                 # First-run wizard
runvo add [name path desc]  # Add project (interactive or one-liner)
runvo remove <name>         # Remove project
runvo list                  # List projects
runvo config                # Edit projects.conf in $EDITOR

# Prompt management
runvo prompts               # List all prompts (shipped + custom)
runvo prompt add <name>     # Create custom prompt
runvo prompt edit <name>    # Edit prompt in $EDITOR
runvo prompt rm <name>      # Delete custom prompt

# Utilities
runvo sessions              # Active tmux sessions
runvo history               # Recent run history
runvo update                # Check & install updates
runvo version               # Show version info
runvo help                  # Full help
```

## Remote Access (Phone)

Three steps to run AI agents from your iPhone:

1. **Mac** — Enable Remote Login: `System Settings → General → Sharing → Remote Login`
2. **Tailscale** — Install on Mac + iPhone, login same account. Note `100.x.x.x` IP.
3. **Termius** — Add SSH host with Tailscale IP. Connect and run `runvo`.

No static IP, no port forwarding. Tailscale handles everything.

## Configuration

### Projects (`~/.runvo/projects.conf`)

```
# name | path | description
my-backend | ~/Projects/my-backend | Backend API
my-app     | ~/Projects/my-app     | Side project
```

Manage with `runvo add`, `runvo remove`, or `runvo config`.

### Prompts

**Shipped** prompts live in the repo `prompts/` dir: `review`, `fix-lint`, `test`, `status`.

**Custom** prompts go in `~/.runvo/prompts/custom/` (git-ignored). Create with `runvo prompt add <name>`. Custom prompts with the same name override shipped ones.

### Agent Config (`~/.runvo/config`)

```
RUNVO_AGENT=claude
RUNVO_AGENT_PROMPT_FLAG=-p
```

Auto-detected on first run. Supports `claude` (`-p` flag) and `aider` (`--message` flag). Any CLI agent works if you set the correct prompt flag.

## Requirements

- **tmux** — session persistence
- **AI CLI** — Claude Code, Aider, or any CLI-based agent
- **gum** — optional, for prettier menus (auto-fallback to plain text)
- **Tailscale** + **Termius** — for phone access (optional)

## Contributing

1. Fork the repo
2. Create a branch (`git checkout -b feature/my-feature`)
3. Commit changes (`git commit -m "Add my feature"`)
4. Push (`git push origin feature/my-feature`)
5. Open a PR

## License

[MIT](LICENSE)
