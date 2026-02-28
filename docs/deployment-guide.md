# Deployment Guide — runvo

## Installation Methods

### 1. Homebrew (recommended)

```bash
brew tap runvo/runvo
brew install runvo
```

### 2. Curl one-liner

```bash
curl -fsSL https://raw.githubusercontent.com/runvo/runvo/master/install.sh | bash
```

### 3. Manual / Dev setup

```bash
git clone https://github.com/runvo/runvo.git ~/.runvo
source ~/.runvo/setup.sh
```

## What install.sh Does

1. Checks git is installed
2. Installs tmux via brew if missing (macOS)
3. Optionally installs gum (better TUI)
4. Clones repo to `~/.runvo` (or updates if exists)
5. Creates `~/.runvo/prompts/custom/`
6. Injects shell function into `.zshrc` and `.bashrc`:
   ```bash
   # >>> runvo >>>
   runvo() { bash "$HOME/.runvo/runvo.sh" "$@" }
   # <<< runvo <<<
   ```
7. Detects AI agent (claude or aider)
8. Runs setup wizard (interactive installs only; skip with `--unattended`)

## Dependencies

| Tool | Required | Install |
|------|----------|---------|
| git | Yes | `brew install git` / `apt install git` |
| tmux | Yes | `brew install tmux` / `apt install tmux` |
| bash | Yes | Pre-installed |
| AI CLI | Yes | `npm i -g @anthropic-ai/claude-code` or `pip install aider-chat` |
| gum | No | `brew install gum` (enhanced TUI) |

## Phone Setup (one-time)

### 1. Enable Remote Login (macOS)

`System Settings → General → Sharing → Remote Login` ON

### 2. Install Tailscale

- **Mac**: `brew install tailscale` → login
- **iPhone**: App Store → Tailscale → login same account

### 3. Get Tailscale IP

```bash
tailscale ip -4
# Example: 100.64.123.45
```

### 4. Configure Termius (iPhone)

Add SSH host with Tailscale IP → connect → `runvo`

No static IP, no port forwarding needed.

## Configuration Files

| File | Purpose |
|------|---------|
| `~/.runvo/projects.conf` | Project registry (pipe-delimited) |
| `~/.runvo/config` | Agent config (key=value) |
| `~/.runvo/prompts/custom/` | User custom prompts |
| `~/.runvo/history.log` | Run history |

## Self-Updating

```bash
runvo update    # Check & install updates
```

Uses `git fetch` + `git pull --ff-only` from origin/master. Background check on each startup.

## SSH Auto-Launch

```bash
runvo ssh-auto  # Toggle on/off
```

When enabled, runvo starts automatically on SSH login (detects `$SSH_CONNECTION`).

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `RUNVO_DIR` | `~/.runvo` | Installation directory |
| `RUNVO_AGENT` | Auto-detected | AI agent binary name |
| `RUNVO_AGENT_PROMPT_FLAG` | Auto-detected | Flag for prompt injection |

## Uninstall

```bash
# 1. Remove shell integration (delete marker block in ~/.zshrc and ~/.bashrc)
#    Lines between: # >>> runvo >>> ... # <<< runvo <<<

# 2. Remove installation
rm -rf ~/.runvo

# Homebrew
brew uninstall runvo && brew untap runvo/runvo
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `runvo: command not found` | `source ~/.zshrc` or restart terminal |
| No AI agent found | Install claude-code or aider |
| tmux not found | `brew install tmux` |
| SSH from phone fails | Check Tailscale status, Remote Login enabled |
| Projects not showing | `runvo add my-app ~/path "desc"` |
| Update fails | `cd ~/.runvo && git pull --ff-only origin master` |
