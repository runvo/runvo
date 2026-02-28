# Project Roadmap — runvo

**Current**: v1.0.0 (Stable) | **License**: AGPL-3.0

## Completed (v1.0)

- Interactive project menu (numbers-only, phone-friendly)
- tmux session management with smart resume (continue/new/resume)
- Prompt system: 4 shipped (review, fix-lint, test, status) + custom with override
- Quick mode CLI: `runvo <n> [action|c "prompt"|i]`
- SSH auto-launch toggle
- Self-updating via git (background check + interactive install)
- Agent-agnostic: claude, aider, or any CLI with configurable flag
- Setup wizard + installer (Homebrew tap + curl one-liner)
- History logging (last 100 entries)
- gum TUI with plain bash fallback
- Guide website: runvo.github.io

## Short-Term (v1.1–v1.2)

### v1.1 — Quality & Compatibility

- [ ] Linux support — test/fix on Ubuntu, Debian (tmux + bash differences)
- [ ] Prompt variables — `${PROJECT_NAME}`, `${PROJECT_PATH}`, `${BRANCH}` template support
- [ ] Session cleanup — `runvo sessions --clean` to remove stale sessions
- [ ] Better error messages — clearer feedback when deps fail
- [ ] Project validation — warn on invalid paths during load

### v1.2 — Convenience

- [ ] Action aliases — `runvo <n> r` shorthand for "review"
- [ ] Project groups/tags — simple categorization in projects.conf
- [ ] Session search — find/resume sessions by keyword
- [ ] Prompt parameters — allow args in custom prompts
- [ ] Config migration — smooth upgrades when format changes

## Medium-Term (v2.0)

### Workflows & Multi-Agent

- [ ] Multi-agent sessions — run multiple agents in same session
- [ ] Agent chains — define workflows: agent1 writes → agent2 reviews
- [ ] Output capture — save/replay agent responses, export to Markdown
- [ ] Custom hooks — pre/post-action scripts (`~/.runvo/hooks/`)
- [ ] Prompt composition — combine prompts with conditionals
- [ ] Session templates — pre-configured agent behavior per project

### Integration

- [ ] Notification hooks — Slack, Discord, email on completion
- [ ] Web dashboard (read-only) — view sessions/history from browser
- [ ] Plugin system — `~/.runvo/plugins/*.sh` for custom commands
- [ ] Docker image — containerized runvo for CI/automation

## Long-Term / Ideas (v3.0+)

- Team mode — shared projects/prompts via Tailscale
- Prompt marketplace — community-contributed prompts
- Smart prompt suggestion — analyze code context, recommend prompts
- Cost tracking — token usage per session/project
- Batch operations — `runvo batch <prompt> <projects...>`
- IDE plugins — VSCode, Vim for runvo control
- Mobile app — native iOS/Android (if SSH becomes friction)

## Design Principles

1. **Phone-first** — every feature must work on small screens, number menus
2. **Single bash script** — keep core lightweight; plugins for complexity
3. **SSH-first** — remote/Tailscale is primary; local is secondary
4. **Agent-agnostic** — support any CLI, no vendor lock-in
5. **Zero-config ideal** — auto-detect, setup wizard, minimal maintenance

## Not Planned

- Full GUI/web app (CLI is the product)
- Database backend (file-based config is sufficient)
- Real-time collaboration (out of scope)
- Proprietary agent integrations (open-source only)
