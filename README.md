<p align="center">
  <img src="logo.png" alt="runvo" width="120">
</p>

<h1 align="center">runvo</h1>

<p align="center">Mobile command center for AI coding agents. Run Claude Code, Aider, or any AI CLI from your phone via SSH.</p>

[![Guide](https://img.shields.io/badge/Setup_Guide-runvo.github.io-f2a8c2?style=flat-square)](https://runvo.github.io) [![GitHub](https://img.shields.io/github/stars/runvo/runvo?style=flat-square&label=GitHub)](https://github.com/runvo/runvo) [![License](https://img.shields.io/badge/license-AGPLv3-blue?style=flat-square)](LICENSE)

## Install

```bash
# Homebrew (recommended)
brew tap runvo/runvo
brew install runvo

# Or one-liner
curl -fsSL https://raw.githubusercontent.com/runvo/runvo/master/install.sh | bash
```

Requires: `git`, `tmux`, and an AI CLI (`claude` or `aider`).

## Quick Start

```bash
# 1. Install (see above)

# 2. Add a project
runvo add my-app ~/Projects/my-app "My App"

# 3. Run — pick project, start chatting
runvo
```

That's it. Type a number, press Enter, chat with your AI agent.

## Usage

```bash
# Interactive — pick project → chat
runvo                       # Show projects, type number → chat
runvo <n>                   # Open project #n directly

# One-shot commands
runvo <n> <a>               # Run preset action #a on project #n
runvo <n> c "fix the bug"   # Custom prompt on project #n
runvo <n> i                 # Interactive session on project #n

# Project management
runvo new [name]            # Create new project (mkdir + git init + register)
runvo add [name path desc]  # Register existing project
runvo clone <url> [name]    # Clone repo & register in one step
runvo edit [n|name]         # Open project in editor
runvo remove <name>         # Remove project
runvo list                  # List projects
runvo status                # Git status dashboard for all projects
runvo config                # Edit projects.conf in $EDITOR
runvo setup                 # Setup wizard

# Prompt management
runvo prompts               # List all prompts (shipped + custom)
runvo prompt add <name>     # Create custom prompt
runvo prompt edit <name>    # Edit prompt in $EDITOR
runvo prompt rm <name>      # Delete custom prompt

# Remote control (no attach needed!)
runvo send <n> "fix bug"    # Send prompt to running session
runvo peek [n]              # View session output without attaching
runvo attach [name|n]       # Quick attach to session

# Utilities
runvo sessions              # Active tmux sessions
runvo kill [name|all]       # Kill session(s)
runvo history               # Recent run history
runvo update                # Check & install updates
runvo ssh-auto              # Toggle SSH auto-launch
runvo doctor                # Check system health & dependencies
runvo version               # Show version
runvo help                  # Full help
```

## Server Setup

runvo runs on **macOS**, **Linux**, or **Windows (WSL)**.

```bash
# macOS
brew tap runvo/runvo && brew install runvo

# Linux / WSL
sudo apt install -y tmux git
curl -fsSL https://raw.githubusercontent.com/runvo/runvo/master/install.sh | bash
```

## Phone Setup (one-time)

Works with **iPhone** and **Android**.

1. **Computer** — Enable SSH + install [Tailscale](https://tailscale.com/download)
   - macOS: `System Settings → General → Sharing → Remote Login` ON
   - Linux: `sudo apt install openssh-server`
   - Windows WSL: `sudo apt install openssh-server` (use port 2222)
2. **Phone** — Install [Tailscale](https://tailscale.com/download) ([iOS](https://apps.apple.com/app/tailscale/id1470499037) / [Android](https://play.google.com/store/apps/details?id=com.tailscale.ipn)) — login same account
3. **Phone** — Install [Termius](https://termius.com) ([iOS](https://apps.apple.com/app/termius-terminal-ssh-client/id549039908) / [Android](https://play.google.com/store/apps/details?id=com.server.auditor.ssh.client)) — add SSH host with Tailscale IP (`tailscale ip -4`)

No static IP, no port forwarding. Tailscale handles everything.

## Configuration

### Projects (`~/.runvo/projects.conf`)

```
# name | path | description | agent (optional)
my-backend | ~/Projects/my-backend | Backend API | claude
my-app     | ~/Projects/my-app     | Side project | aider
frontend   | ~/Projects/frontend   | React app
```

Per-project `agent` field is optional — falls back to global config. Manage with `runvo add`, `runvo remove`, or `runvo config`.

### Prompts

**Shipped**: `review`, `fix-lint`, `test`, `status` (in repo `prompts/` dir).

**Custom**: `~/.runvo/prompts/custom/` (git-ignored). Create with `runvo prompt add <name>`. Same-name custom prompts override shipped.

### Agent (`~/.runvo/config`)

```
RUNVO_AGENT=claude
RUNVO_AGENT_PROMPT_FLAG=-p
```

Auto-detected on first run. Built-in support for `claude` (`-p`) and `aider` (`--message`). Any CLI agent works — just set the flag.

## Requirements

- **tmux** — session persistence (macOS, Linux, WSL)
- **AI CLI** — Claude Code, Aider, or any CLI agent
- **Tailscale** + **Termius** — for phone access (optional, iOS & Android)

## Contributing

1. Fork → branch → commit → push → PR

## Author

**Tran Thai Hoang** — [admi@tranthaihoang.com](mailto:admi@tranthaihoang.com)

## License

[AGPL-3.0](LICENSE)
