#!/usr/bin/env bash
# select-models.sh — Interactive model selector for the pipeline
# Uses fzf (preferred) or numbered prompt to pick models per role
set -euo pipefail

CACHE_FILE="${HOME}/.cache/opencode/models.json"
AGENTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/agents"

echo "==> Interactive Model Selector"
echo ""

if [[ ! -f "$CACHE_FILE" ]]; then
  echo "    ✗ models cache not found at $CACHE_FILE"
  echo "    Run 'opencode' once to populate it."
  exit 1
fi

# Extract free models into a selectable list
python3 <<PYEOF
import json

with open("$CACHE_FILE") as f:
    data = json.load(f)

opencode = data.get('opencode', {})
models = opencode.get('models', {})

free = []
for mid, m in models.items():
    if not isinstance(m, dict):
        continue
    cost = m.get('cost', {})
    status = m.get('status', '')
    if isinstance(cost, dict) and cost.get('input', 1) == 0 and status != 'deprecated':
        free.append({
            "id": mid,
            "name": m.get('name', mid),
            "reasoning": m.get('reasoning', False),
            "tool_call": m.get('tool_call', False),
            "structured_output": m.get('structured_output', False),
            "context": m.get('limit', {}).get('context', 0),
            "output": m.get('limit', {}).get('output', 0),
        })

# Write free models list for fzf
with open("/tmp/opencode-free-models.json", 'w') as f:
    json.dump(free, f, indent=2)

print(f"Found {len(free)} free models")
PYEOF

# Determine picker: fzf > numbered prompt
USE_FZF=false
if command -v fzf &>/dev/null; then
  USE_FZF=true
fi

ROLES=("pipeline" "planner" "debater" "implementer" "reviewer" "tester" "linter" "commit-msg")

for role in "${ROLES[@]}"; do
  AGENT_FILE="$AGENTS_DIR/$role.md"
  if [[ ! -f "$AGENT_FILE" ]]; then
    echo "    ⚠ $role.md not found — skipping"
    continue
  fi

  # Read current model
  CURRENT=$(grep -E '^model: ' "$AGENT_FILE" | sed 's/^model: opencode\///')
  echo ""
  echo "── $role ── (current: $CURRENT)"

  if $USE_FZF; then
    SELECTED=$(python3 -c "
import json
with open('/tmp/opencode-free-models.json') as f:
    models = json.load(f)
for m in models:
    tags = []
    if m['reasoning']: tags.append('reasoning')
    if m['tool_call']: tags.append('tool_call')
    if m['structured_output']: tags.append('structured')
    ctx = f\"{m['context']//1000}k\" if m['context'] else '?'
    out = f\"{m['output']//1000}k\" if m['output'] else '?'
    print(f\"{m['id']:40s} {m['name']:35s} {','.join(tags):20s} ctx={ctx} out={out}\")
" | fzf --prompt="Model for $role > " --height=20 | awk '{print $1}')

    if [[ -z "$SELECTED" ]]; then
      echo "    → skipped"
      continue
    fi
  else
    echo "  Available models:"
    python3 -c "
import json
with open('/tmp/opencode-free-models.json') as f:
    models = json.load(f)
for i, m in enumerate(models, 1):
    tags = []
    if m['reasoning']: tags.append('reasoning')
    if m['tool_call']: tags.append('tool_call')
    if m['structured_output']: tags.append('structured')
    ctx = f\"{m['context']//1000}k\" if m['context'] else '?'
    print(f\"  {i:2d}. {m['id']:35s} [{','.join(tags)}] ctx={ctx}\")
"
    read -p "  Enter number (or 0 to skip): " choice
    if [[ "$choice" -eq 0 || -z "$choice" ]]; then
      echo "    → skipped"
      continue
    fi
    SELECTED=$(python3 -c "
import json
with open('/tmp/opencode-free-models.json') as f:
    models = json.load(f)
idx = int('$choice') - 1
if 0 <= idx < len(models):
    print(models[idx]['id'])
")
    if [[ -z "$SELECTED" ]]; then
      echo "    → invalid choice, skipped"
      continue
    fi
  fi

  # Update agent file
  sed -i "s/^model: opencode\/.*$/model: opencode\/$SELECTED/" "$AGENT_FILE"
  echo "    ✓ $role → $SELECTED"
done

rm -f /tmp/opencode-free-models.json

echo ""
echo "==> ✓ All selections applied."
echo "    Run 'opencode' to use the new models."
