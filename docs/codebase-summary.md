# Codebase Summary — runvo

**Version**: 1.0.0 | **Language**: Bash | **License**: AGPL-3.0

## File Structure

```
runvo/
├── runvo.sh          # Main script (982 lines) — all CLI logic
├── install.sh        # Installer (150 lines) — curl one-liner + Homebrew
├── setup.sh          # Dev setup (44 lines) — source for local dev
├── projects.conf     # Example project registry template
├── .gitignore        # Ignores user config, custom prompts, logs
├── LICENSE           # AGPL-3.0
├── README.md         # User-facing documentation (114 lines)
├── prompts/          # Shipped prompt templates
│   ├── review.txt    # Review recent changes, flag concerns
│   ├── fix-lint.txt  # Fix all lint and type errors
│   ├── status.txt    # Show git status and recent commits
│   ├── test.txt      # Run test suite, report results
│   └── custom/       # User custom prompts (gitignored)
├── docs/             # Project documentation
└── plans/            # Implementation plans
    └── reports/
```

## runvo.sh Breakdown (982 lines)

| Section | Lines | Functions |
|---------|-------|-----------|
| Header & Paths | 1–20 | Version, directory constants, mkdir |
| Colors | 22–31 | ANSI color constants (pink theme) |
| Config | 33–59 | `load_config()`, `save_config()` |
| gum TUI helpers | 61–108 | `choose_item()`, `confirm_action()`, `input_text()` |
| Agent detection | 110–131 | `detect_agent()`, `get_agent_flag()` |
| Dependency check | 133–146 | `check_deps()` |
| Project loading | 148–169 | `load_projects()` — parse projects.conf |
| Prompt loading | 171–196 | `load_prompts()` — shipped + custom with override |
| History | 198–222 | `log_history()`, `show_history()` |
| Agent: prompt mode | 224–257 | `run_agent_prompt()` — one-shot execution |
| Agent: interactive | 259–307 | `run_agent_interactive()` — tmux session with smart resume |
| Session listing | 309–327 | `show_sessions()` |
| Display helpers | 329–360 | `display_projects()`, `display_actions()` |
| Banner | 362–367 | `show_banner()` |
| Version & Update | 369–423 | `get_version()`, `check_update()`, `do_update()` |
| Setup wizard | 425–496 | `run_setup_wizard()` |
| Project management | 498–561 | `cmd_add_project()`, `cmd_remove_project()` |
| Prompt management | 563–656 | `cmd_list_prompts()`, `cmd_add_prompt()`, `cmd_edit_prompt()`, `cmd_remove_prompt()` |
| Main menu | 658–699 | `main_menu()` — project selection + shortcuts |
| Task flow | 701–752 | `run_task_flow()` — project → action → execute |
| Quick mode | 762–792 | `run_quick()` — direct CLI `runvo <n> [action]` |
| Help | 794–832 | `show_help()` |
| SSH auto-launch | 834–885 | `cmd_ssh_auto()` — toggle auto-start on SSH login |
| Main entrypoint | 887–982 | CLI arg parsing, fallback to interactive |

## install.sh (150 lines)

1. Check git dependency
2. Install tmux via brew (if missing)
3. Optionally install gum
4. Clone/update repo to `~/.runvo`
5. Create user dirs (`~/.runvo/prompts/custom/`)
6. Inject shell function into `.zshrc`/`.bashrc` (marker-based)
7. Detect AI agent (claude or aider)
8. Run setup wizard (interactive installs only)

## setup.sh (44 lines)

Dev helper — `source setup.sh` injects `runvo()` shell function pointing to local `./runvo.sh` for immediate testing.

## Data Storage

| File | Format | Purpose |
|------|--------|---------|
| `~/.runvo/projects.conf` | Pipe-delimited (`name \| path \| desc`) | Project registry |
| `~/.runvo/config` | Key=value | Agent name + prompt flag |
| `~/.runvo/prompts/custom/*.txt` | Plain text | User custom prompts |
| `~/.runvo/history.log` | Pipe-delimited (`ts\|project\|action\|status`) | Run history (last 100) |

## Key Design Decisions

1. **Single bash file** — No build step, no compilation, instant portability
2. **Numbers-only navigation** — Designed for phone keyboards (no arrow keys)
3. **gum optional** — Graceful fallback to plain bash read/echo
4. **tmux persistence** — Sessions survive SSH disconnects
5. **Agent-agnostic** — Flag-based prompt injection works with any CLI
6. **User config in ~/.runvo/** — Git-ignored, survives updates
7. **Shipped + custom prompts** — Custom overrides shipped by filename match
8. **Marker-based shell injection** — Idempotent, safe to re-run installer

## Dependencies

| Tool | Required | Purpose |
|------|----------|---------|
| git | Yes | Clone/update runvo, version info |
| tmux | Yes | Session persistence |
| bash | Yes | Shell execution |
| AI CLI | Yes | Claude Code or Aider (or any CLI agent) |
| gum | No | Enhanced TUI (charmbracelet) |
| curl | Install only | Download installer script |
