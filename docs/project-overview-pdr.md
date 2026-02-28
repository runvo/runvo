# Project Overview & PDR — runvo

## Product Vision

**runvo** is a mobile command center for AI coding agents. It lets developers run Claude Code, Aider, or any AI CLI from their phone via SSH — using a phone-friendly TUI with numbers-only navigation and tmux session persistence.

**Repository**: [github.com/runvo/runvo](https://github.com/runvo/runvo)
**Website**: [runvo.github.io](https://runvo.github.io)
**Version**: 1.0.0 | **License**: AGPL-3.0 | **Language**: Bash

## Target Users

- Developers who use AI coding agents (Claude Code, Aider) daily
- Mobile-first workflow: want to start/monitor AI coding from phone while away from desk
- SSH users comfortable with terminal workflows
- Solo developers and small teams managing multiple projects

## Core Features

| Feature | Description |
|---------|-------------|
| Interactive menu | Number-based project selection, phone-optimized (no arrow keys) |
| tmux sessions | Persistent AI sessions that survive SSH disconnects |
| Smart resume | Continue existing / new / resume last chat when session exists |
| Prompt system | 4 shipped prompts + user custom with name-based override |
| Quick mode | `runvo <n> [action]` for direct CLI execution |
| SSH auto-launch | Toggle auto-start on SSH login via shell rc injection |
| Self-updating | Git-based update check and install |
| Agent-agnostic | Supports claude (`-p`), aider (`--message`), or any CLI with configurable flag |
| Setup wizard | First-run interactive configuration |
| History logging | Track recent runs with status (last 100, display last 20) |
| gum TUI | Enhanced UI with graceful fallback to plain bash |

## Non-Functional Requirements

- **Portability**: Single bash script, no compilation, no build step
- **Phone UX**: All interactions via number keys + Enter (no arrow keys, no ctrl sequences)
- **Zero-config**: Auto-detect agent on install, setup wizard for projects
- **Resilience**: tmux sessions persist across SSH disconnects and reconnects
- **Lightweight**: No external dependencies beyond git, tmux, bash, and an AI CLI
- **Idempotent install**: Safe to re-run installer without duplication

## Technical Stack

- **Language**: Bash (~982 lines main script)
- **Session management**: tmux
- **TUI**: gum (optional, with plain bash fallback)
- **Installation**: Homebrew tap + curl one-liner
- **Configuration**: Plain text files (pipe-delimited, key=value)
- **Networking**: Tailscale (for phone SSH access)

## Success Metrics

- Install-to-first-run in under 2 minutes
- Works on any phone SSH client (Termius, Prompt, etc.)
- Session resume after disconnect with zero data loss
- Support any AI CLI without code changes (config-only)

## Architecture Summary

```
iPhone (Termius) → SSH → Mac → runvo.sh → tmux → AI CLI (claude/aider)
```

Single entrypoint (`runvo.sh`) handles all logic: project management, prompt system, session management, agent abstraction, history, updates, and TUI.

User data stored in `~/.runvo/` (git-ignored, survives updates).

## Future Considerations

- Linux support (test/fix platform differences)
- Prompt template variables (`${PROJECT_NAME}`, `${BRANCH}`)
- Multi-agent workflows (chain agents)
- Output capture and export
- Notification hooks (Slack, Discord on completion)
- Plugin system for custom commands
