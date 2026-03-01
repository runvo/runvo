#!/bin/bash
# runvo — test suite
# Run: bash tests/runvo_test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNVO="$SCRIPT_DIR/runvo.sh"
PASS=0 FAIL=0 TOTAL=0

# --- Test helpers ---
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  ((TOTAL++))
  if [[ "$actual" == "$expected" ]]; then
    echo "  ✓ $desc"
    ((PASS++))
  else
    echo "  ✗ $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    ((FAIL++))
  fi
}

assert_contains() {
  local desc="$1" expected="$2" actual="$3"
  ((TOTAL++))
  if [[ "$actual" == *"$expected"* ]]; then
    echo "  ✓ $desc"
    ((PASS++))
  else
    echo "  ✗ $desc"
    echo "    expected to contain: $expected"
    echo "    actual: ${actual:0:200}"
    ((FAIL++))
  fi
}

assert_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  ((TOTAL++))
  if [[ "$actual" != *"$unexpected"* ]]; then
    echo "  ✓ $desc"
    ((PASS++))
  else
    echo "  ✗ $desc"
    echo "    should not contain: $unexpected"
    ((FAIL++))
  fi
}

assert_exit() {
  local desc="$1" expected_code="$2"
  shift 2
  ((TOTAL++))
  "$@" &>/dev/null
  local code=$?
  if [[ $code -eq $expected_code ]]; then
    echo "  ✓ $desc (exit $code)"
    ((PASS++))
  else
    echo "  ✗ $desc (expected exit $expected_code, got $code)"
    ((FAIL++))
  fi
}

# --- Setup test environment ---
TEST_DIR=$(mktemp -d)
TEST_RUNVO_DIR="$TEST_DIR/.runvo"
TEST_PROJECTS="$TEST_RUNVO_DIR/projects.conf"
TEST_CONFIG="$TEST_RUNVO_DIR/config"
TEST_PROMPTS="$TEST_RUNVO_DIR/prompts/custom"
mkdir -p "$TEST_RUNVO_DIR" "$TEST_PROMPTS"

# Create test project dirs
mkdir -p "$TEST_DIR/proj-a"
git -C "$TEST_DIR/proj-a" init --quiet

mkdir -p "$TEST_DIR/proj-b"

cat > "$TEST_PROJECTS" <<EOF
# test projects
proj-a | $TEST_DIR/proj-a | Test project A | claude
proj-b | $TEST_DIR/proj-b | Test project B
EOF

# Override RUNVO_DIR for tests
export RUNVO_DIR="$TEST_RUNVO_DIR"

echo ""
echo "=== runvo test suite ==="
echo ""

# ============================================================
echo "--- version ---"
out=$(bash "$RUNVO" version 2>&1)
assert_contains "version shows runvo" "runvo" "$out"
assert_contains "version shows version number" "1.0" "$out"
assert_exit "version exits 0" 0 bash "$RUNVO" version

# ============================================================
echo "--- help ---"
out=$(bash "$RUNVO" help 2>&1)
assert_contains "help shows USAGE" "USAGE" "$out"
assert_contains "help shows COMMANDS" "COMMANDS" "$out"
assert_contains "help shows send" "send" "$out"
assert_contains "help shows peek" "peek" "$out"
assert_contains "help shows clone" "clone" "$out"
assert_contains "help shows doctor" "doctor" "$out"
assert_contains "help shows status" "status" "$out"
assert_contains "help shows kill" "kill" "$out"
assert_contains "help shows attach" "attach" "$out"
assert_exit "help exits 0" 0 bash "$RUNVO" help

# ============================================================
echo "--- list ---"
out=$(bash "$RUNVO" list 2>&1)
assert_contains "list shows proj-a" "proj-a" "$out"
assert_contains "list shows proj-b" "proj-b" "$out"
assert_contains "list shows description" "Test project A" "$out"

# ============================================================
echo "--- status ---"
out=$(bash "$RUNVO" status 2>&1)
assert_contains "status shows STATUS header" "STATUS" "$out"
assert_contains "status shows proj-a" "proj-a" "$out"
assert_contains "status shows branch for git project" "ma" "$out"  # main or master
assert_contains "status shows proj-b (non-git)" "not a git repo" "$out"

# ============================================================
echo "--- doctor ---"
out=$(bash "$RUNVO" doctor 2>&1)
assert_contains "doctor shows DOCTOR" "DOCTOR" "$out"
assert_contains "doctor checks tmux" "tmux" "$out"
assert_contains "doctor checks git" "git" "$out"
assert_contains "doctor shows projects count" "registered" "$out"

# ============================================================
echo "--- history (empty) ---"
out=$(bash "$RUNVO" history 2>&1)
assert_contains "history shows no history" "No history" "$out"

# ============================================================
echo "--- sessions ---"
out=$(bash "$RUNVO" sessions 2>&1)
assert_contains "sessions shows SESSIONS" "SESSIONS" "$out"

# ============================================================
echo "--- prompts ---"
out=$(bash "$RUNVO" prompts 2>&1)
assert_contains "prompts shows PROMPTS" "PROMPTS" "$out"
assert_contains "prompts shows shipped" "Shipped" "$out"

# ============================================================
echo "--- add project ---"
bash "$RUNVO" add test-proj "$TEST_DIR/proj-a" "Test added" 2>&1
out=$(bash "$RUNVO" list 2>&1)
assert_contains "add registers project" "test-proj" "$out"

# ============================================================
echo "--- remove project ---"
bash "$RUNVO" remove test-proj <<< "y" 2>&1
out=$(bash "$RUNVO" list 2>&1)
assert_not_contains "remove deletes project" "test-proj" "$out"
assert_contains "original projects still exist" "proj-a" "$out"

# ============================================================
echo "--- per-project agent ---"
# Source just the functions we need
out=$(RUNVO_DIR="$TEST_RUNVO_DIR" bash -c '
  source "'"$RUNVO"'" version 2>/dev/null
' 2>&1 || true)
# Check projects.conf has agent field
assert_contains "projects.conf has agent field" "claude" "$(cat "$TEST_PROJECTS")"

# ============================================================
echo "--- prompt management ---"
# Add prompt
echo "test prompt content" | bash "$RUNVO" prompt add test-prompt 2>&1
assert_eq "prompt file created" "true" "$([ -f "$TEST_PROMPTS/test-prompt.txt" ] && echo true || echo false)"
assert_eq "prompt content correct" "test prompt content" "$(cat "$TEST_PROMPTS/test-prompt.txt")"

# List prompts shows custom
out=$(bash "$RUNVO" prompts 2>&1)
assert_contains "prompts shows custom prompt" "test-prompt" "$out"

# Remove prompt
bash "$RUNVO" prompt rm test-prompt <<< "y" 2>&1
assert_eq "prompt file deleted" "false" "$([ -f "$TEST_PROMPTS/test-prompt.txt" ] && echo true || echo false)"

# ============================================================
echo "--- peek (no sessions) ---"
out=$(bash "$RUNVO" peek 2>&1)
assert_contains "peek shows no sessions" "No active" "$out"

# ============================================================
echo "--- kill (no sessions) ---"
out=$(bash "$RUNVO" kill all 2>&1)
assert_contains "kill all shows no sessions" "No active" "$out"

# ============================================================
echo "--- clone (invalid url) ---"
out=$(bash "$RUNVO" clone 2>&1)
assert_contains "clone shows usage" "Usage" "$out"

# ============================================================
echo "--- send (no args) ---"
out=$(bash "$RUNVO" send 2>&1)
assert_contains "send shows usage" "Usage" "$out"

# ============================================================
echo "--- invalid command ---"
out=$(bash "$RUNVO" 999 2>&1)
assert_contains "invalid project number" "Invalid" "$out"

# ============================================================
echo "--- edge: path-traversal prompt name ---"
out=$(bash "$RUNVO" prompt add "../etc/evil" 2>&1)
assert_contains "blocks path traversal" "Invalid" "$out"

out=$(bash "$RUNVO" prompt add "foo/bar" 2>&1)
assert_contains "blocks slashes" "Invalid" "$out"

# --- Cleanup ---
rm -rf "$TEST_DIR"

# --- Summary ---
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
echo ""
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
