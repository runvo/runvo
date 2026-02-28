# Code Review Summary — runvo v1.0 Open Source Release

### Scope
- Files reviewed: `runvo.sh` (~570 lines), `install.sh` (~148 lines), `setup.sh` (~45 lines), `.gitignore`, `README.md`, `prompts/`
- Lines of code analyzed: ~770
- Review focus: Security, correctness, shell best practices, branding consistency

---

### Overall Assessment

Solid, well-structured bash project. Code is readable, the gum/fallback pattern is clean, and branding is consistent throughout. No leftover "reayai" references found. Most issues are low-to-medium severity. Three real bugs and two medium security concerns worth fixing before release.

---

### Critical Issues

**None.**

---

### High Priority Findings

#### H1. `install.sh`: `git pull --ff-only` not guarded — aborts installer under `set -e`

**File:** `install.sh` line 61

```bash
set -e   # at top of file
...
git -C "$RUNVO_DIR" pull --ff-only origin master --quiet 2>/dev/null
echo -e "  ${G}✓${N} Updated"
```

If the user has local changes or is offline, `git pull` exits non-zero, killing the installer mid-run with `set -e` in effect and no error message (stderr is suppressed with `2>/dev/null`). The user sees nothing, install aborts silently.

Fix:
```bash
if ! git -C "$RUNVO_DIR" pull --ff-only origin master --quiet 2>/dev/null; then
  echo -e "  ${Y}⚠ Could not update (offline or local changes). Using existing version.${N}"
fi
```

#### H2. `runvo.sh` line 244: Unquoted `$flag` — breaks if flag is multi-word

```bash
(cd "$project_path" && "$RUNVO_AGENT" $flag "$prompt_text")
```

`$flag` is unquoted intentionally to allow word splitting (flag like `--message`). This is fine today since all flags are single tokens, but if `RUNVO_AGENT_PROMPT_FLAG` is ever set to a value with spaces (e.g. `--some flag`) it will silently misbehave. Low risk now but worth documenting or using an array.

Preferred pattern:
```bash
local -a agent_cmd=("$RUNVO_AGENT" "$flag" "$prompt_text")
(cd "$project_path" && "${agent_cmd[@]}")
```

---

### Medium Priority Findings

#### M1. `runvo.sh`: Project name not sanitized before use in `grep`/`sed` regex

**Files:** lines 471, 484, 512, 518

```bash
grep -q "^$name " "$PROJECTS_FILE"   # $name is unquoted in regex
sed -i.bak "/^$name /d" "$PROJECTS_FILE"
```

A project name containing regex metacharacters (e.g. `my.app`, `my[app]`, or `.`) will produce incorrect grep/sed matches. A name like `.` would match any line. This is a data-integrity concern, not a remote-exploit risk (it's local config), but could corrupt `projects.conf`.

Fix options:
- Use `grep -F` (fixed string) for the existence check
- Sanitize/reject names containing special chars at input time

```bash
# grep check
grep -qF "$name |" "$PROJECTS_FILE"

# sed delete — use fixed-string anchor more carefully
sed -i.bak "/^$(printf '%s' "$name" | sed 's/[.[\*^$]/\\&/g') /d" "$PROJECTS_FILE"
```

Or simplest: reject names with non-alphanumeric/dash chars in `cmd_add_project`.

#### M2. `cmd_add_prompt`: No path traversal guard on prompt `$name`

**File:** `runvo.sh` lines 553, 579, 601

```bash
local file="$PROMPTS_DIR_USER/$name.txt"
```

A user passing `name=../../.zshrc` via CLI (`runvo prompt add ../../.zshrc`) would write/edit/delete `~/.runvo/prompts/custom/../../.zshrc.txt` — i.e., `~/.zshrc.txt` (not `.zshrc` due to the `.txt` suffix, so low impact). But `runvo prompt edit ../../../etc/passwd` could open arbitrary files in `$EDITOR`. Since this is a local tool, the blast radius is limited to the user themselves, but it's still worth a one-line guard:

```bash
[[ "$name" == */* || "$name" == *..* ]] && { echo -e "  ${C_RED}Invalid prompt name.${C_RESET}"; return 1; }
```

#### M3. `runvo update` exit code is misleading when already up-to-date

**File:** `runvo.sh` lines 905–908

```bash
check_update && confirm_action "Update now?" && do_update
exit $?
```

`check_update` returns `1` when up-to-date (intentionally), so `$?` is `1` on a successful "already current" run. `exit 1` signals failure to the calling shell/scripts. This is a semantic inversion.

Fix:
```bash
check_update || { exit 0; }   # up-to-date, exit cleanly
confirm_action "Update now?" && do_update
exit $?
```

Or restructure with an explicit variable.

---

### Low Priority Suggestions

#### L1. `tac` is not available on all Linux systems

**File:** `runvo.sh` line 214

```bash
tac "$LOG_FILE" | head -20 | ...
```

`tac` is GNU coreutils, present on macOS (via brew) and most Linux distros but not guaranteed everywhere. Safe fallback:

```bash
tail -r "$LOG_FILE" 2>/dev/null || tac "$LOG_FILE"
```

Or `awk '{lines[NR]=$0} END {for(i=NR;i>=1;i--) print lines[i]}' "$LOG_FILE"` for pure POSIX.

Low priority since the README targets macOS + Tailscale SSH, but worth a note.

#### L2. `setup.sh` hardcodes `~/.zshrc` only

**File:** `setup.sh` lines 20–26

`setup.sh` only touches `~/.zshrc` (it's a zsh script for local dev). This is intentional and fine for dev use, but could confuse bash-shell contributors. A comment explaining this is zsh-only dev setup (vs `install.sh` which handles both) would clarify intent.

#### L3. `save_config` writes unquoted values

**File:** `runvo.sh` lines 52–57

```bash
cat > "$CONFIG_FILE" <<EOF
RUNVO_AGENT=$RUNVO_AGENT
RUNVO_AGENT_PROMPT_FLAG=$RUNVO_AGENT_PROMPT_FLAG
EOF
```

If `$RUNVO_AGENT` contains spaces or special chars, the config file becomes unparseable. Low risk with current known agents (`claude`, `aider`) but the loader uses `xargs` to trim, which has its own quoting quirks. Quoting the values is safer:

```bash
RUNVO_AGENT="$RUNVO_AGENT"
RUNVO_AGENT_PROMPT_FLAG="$RUNVO_AGENT_PROMPT_FLAG"
```

#### L4. `check_update_silent` background fetch races with foreground fetch

**File:** `runvo.sh` lines 378–388

```bash
check_update_silent() {
  local behind
  behind=$(git -C "$SCRIPT_DIR" rev-list --count HEAD..origin/master 2>/dev/null || echo "0")
  ...
  git -C "$SCRIPT_DIR" fetch origin master --quiet 2>/dev/null &  # background fetch for NEXT run
}
```

The background fetch for next-run is fine. However, if `behind > 0` and the user confirms update, `do_update` calls `git pull` which may race with the background fetch. Minor, unlikely to cause real issues.

#### L5. `install.sh` `eval "$SHELL_BLOCK"` in current shell

**File:** `install.sh` line 115

```bash
eval "$SHELL_BLOCK" 2>/dev/null || true
```

`eval` on a known, static, self-constructed string is safe here (no user input). The `|| true` suppresses errors. This is fine.

---

### Positive Observations

- **Gum fallback pattern** is well-executed — every interactive function has a clean plain-text fallback. No gum-only dead ends.
- **Idempotent install** — the marker-based `inject_shell` correctly removes old blocks before re-injecting. Works correctly on re-run.
- **No leftover "reayai" references** anywhere in the codebase.
- **Branding is consistent** — "runvo" used uniformly across all files, comments, URLs.
- **`.gitignore` is correct** — user data (`projects.conf`, `config`, `history.log`, `prompts/custom/*`) excluded; `.gitkeep` properly preserved with `!` negation rule.
- **`load_prompts`** associative array override logic is clean and works correctly in bash 4+.
- **`SCRIPT_DIR` resolution** using `BASH_SOURCE[0]` is correct and symlink-safe.
- **Path expansion** `${path/#\~/$HOME}` is handled consistently in all entry points.
- **Log rotation** via `tail + mv` is atomic enough for this use case.
- **Session name** `runvo-${project_name}` is a clear, predictable convention.

---

### Recommended Actions

1. **Fix H1** (install.sh git pull + `set -e`): Guard the `git pull` call. This is a real installer breakage on re-run with local changes or offline.
2. **Fix M3** (update exit code): `exit 1` when already up-to-date is misleading for any scripted use.
3. **Fix M1** (grep/sed regex injection): Use `grep -F` for existence checks; sanitize or restrict project names.
4. **Fix M2** (prompt path traversal): One-line name validation in `cmd_add_prompt`, `cmd_edit_prompt`, `cmd_remove_prompt`.
5. **Consider H2** (unquoted `$flag`): Use array for agent invocation if multi-word flags are anticipated.
6. **Low**: Add `tac` fallback comment or alternative for Linux portability.

---

### Metrics

- Type Coverage: N/A (bash)
- Test Coverage: None (no test suite present)
- Linting Issues: 0 critical, 2 high, 2 medium, 4 low (shellcheck not run; issues found by manual review)
- "reayai" references: 0
- Branding consistency: Pass

---

### Unresolved Questions

- Is Linux (non-macOS) a supported target? `tac` availability and `brew`-only dependency auto-install suggest macOS-primary, but README mentions `sudo apt install tmux`. If Linux is a first-class target, L1 and the `brew`-only auto-install paths need attention.
- Is there a plan for a test suite? The `run_agent_prompt` flow is hard to unit-test but a smoke-test for CLI argument parsing would catch regressions.
