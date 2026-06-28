#!/usr/bin/env bash
# install-gpt.sh — Installs the GPT-powered pipeline alongside the free pipeline
# Installs pipeline-gpt (primary) + 8 GPT subagents into ~/.config/opencode/agents/
# Usage: curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/install-gpt.sh | bash
set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
AGENTS_DIR="$CONFIG_DIR/agents"
MANIFEST="$CONFIG_DIR/.opencode-pipeline-gpt-manifest.json"
CONFIG_FILE="$CONFIG_DIR/opencode.json"

GPT_AGENTS=("pipeline-gpt.md" "planner-gpt.md" "debater-gpt.md" "implementer-gpt.md" "reviewer-gpt.md" "security-reviewer-gpt.md" "tester-gpt.md" "linter-gpt.md" "commit-msg-gpt.md")

echo "==> Installing GPT Pipeline alongside your existing free pipeline"
echo "    Target: $AGENTS_DIR"
echo ""

mkdir -p "$AGENTS_DIR"

# 1. Download GPT agent files
echo "==> Downloading GPT agents..."
INSTALLED_FILES=""
for f in "${GPT_AGENTS[@]}"; do
  curl -fsSL "$REPO_URL/gpt/$f" -o "$AGENTS_DIR/$f"
  INSTALLED_FILES="$INSTALLED_FILES\"$f\","
  echo "    ✓ agents/$f"
done
INSTALLED_FILES="[${INSTALLED_FILES%,}]"

# 2. Prompt to set pipeline-gpt as default
echo ""
DEFAULT=""
read -r -p "Set pipeline-gpt as your default agent? [y/N] " DEFAULT
if [[ "$DEFAULT" =~ ^[Yy] ]]; then
  python3 <<PYEOF
import json, os

config_file = "$CONFIG_FILE"

if os.path.exists(config_file):
    with open(config_file) as f:
        config = json.load(f)
else:
    config = {}

config['default_agent'] = 'pipeline-gpt'

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')

print('    default_agent set to pipeline-gpt')
PYEOF
fi

# 3. Write manifest
echo "==> Writing manifest..."
python3 <<PYEOF
import json, datetime

manifest = {
    "version": 1,
    "installed_at": datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    "files": $INSTALLED_FILES
}

with open("$MANIFEST", 'w') as f:
    json.dump(manifest, f, indent=2)

print('    manifest written')
PYEOF

# 4. Ensure state file is gitignored
GITIGNORE="$CONFIG_DIR/.gitignore"
if ! grep -q 'opencode-workflow-state' "$GITIGNORE" 2>/dev/null; then
  echo ".opencode-workflow-state.md" >> "$GITIGNORE" 2>/dev/null || true
  echo "==> Added .opencode-workflow-state.md to global gitignore"
fi

echo ""
echo "==> ✓ GPT Pipeline installed!"
echo ""
echo "    Both pipelines are now available in opencode's agent selector (Tab key):"
echo "      • pipeline      — free OpenCode Zen models"
echo "      • pipeline-gpt — your paid OpenAI models"
echo ""
if [[ ! "$DEFAULT" =~ ^[Yy] ]]; then
  echo "    To switch, press Tab in the opencode TUI and select pipeline-gpt."
  echo "    Or set it as default: opencode.json → \"default_agent\": \"pipeline-gpt\""
fi
echo ""
echo "    To uninstall:"
echo "      curl -fsSL https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master/uninstall-gpt.sh | bash"
