#!/usr/bin/env bash
# select-gpt-models.sh — Interactive GPT model selector for the pipeline-gpt
# Reads ~/.cache/opencode/models.json, lists OpenAI models, assigns per role.
# Uses fzf (preferred) or numbered prompt.
set -euo pipefail

CACHE_FILE="${HOME}/.cache/opencode/models.json"
AGENTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/agents"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROLES_FILE="$SCRIPT_DIR/models/roles.json"

echo "==> GPT Model Selector"
echo "    Lists OpenAI models from your opencode cache."
echo ""

if [[ ! -f "$CACHE_FILE" ]]; then
  echo "    ✗ models cache not found at $CACHE_FILE"
  echo "    Run 'opencode' once to populate it."
  exit 1
fi

# Extract OpenAI models into a selectable list
python3 <<PYEOF
import json

with open("$CACHE_FILE") as f:
    data = json.load(f)

opencode = data.get('opencode', {})
models = opencode.get('models', {})

gpt = []
for mid, m in models.items():
    if not isinstance(m, dict):
        continue
    # Match openai/ prefix models (any cost, any status)
    if mid.startswith('openai/'):
        cost = m.get('cost', {})
        status = m.get('status', '')
        if status == 'deprecated':
            continue
        gpt.append({
            "id": mid,
            "name": m.get('name', mid),
            "reasoning": m.get('reasoning', False),
            "reasoning_options": m.get('reasoning_options'),
            "tool_call": m.get('tool_call', False),
            "structured_output": m.get('structured_output', False),
            "context": m.get('limit', {}).get('context', 0),
            "output": m.get('limit', {}).get('output', 0),
        })

# Also show any model named gpt-5* or containing "gpt" regardless of prefix
for mid, m in models.items():
    if not isinstance(m, dict):
        continue
    name = m.get('name', mid)
    if 'gpt' in mid.lower() or 'gpt' in name.lower():
        if not any(x['id'] == mid for x in gpt):
            cost = m.get('cost', {})
            status = m.get('status', '')
            if status == 'deprecated':
                continue
            gpt.append({
                "id": mid,
                "name": m.get('name', mid),
                "reasoning": m.get('reasoning', False),
                "reasoning_options": m.get('reasoning_options'),
                "tool_call": m.get('tool_call', False),
                "structured_output": m.get('structured_output', False),
                "context": m.get('limit', {}).get('context', 0),
                "output": m.get('limit', {}).get('output', 0),
            })

# Write GPT models list for fzf
with open("/tmp/opencode-gpt-models.json", 'w') as f:
    json.dump(gpt, f, indent=2)

print(f"Found {len(gpt)} GPT models")
PYEOF

# Determine picker: fzf > numbered prompt
USE_FZF=false
if command -v fzf &>/dev/null; then
  USE_FZF=true
fi

ROLES=("pipeline-gpt" "planner-gpt" "debater-gpt" "implementer-gpt" "reviewer-gpt" "security-reviewer-gpt" "tester-gpt" "linter-gpt" "commit-msg-gpt")

for role in "${ROLES[@]}"; do
  AGENT_FILE="$AGENTS_DIR/$role.md"
  if [[ ! -f "$AGENT_FILE" ]]; then
    echo "    ⚠ $role.md not found — skipping"
    continue
  fi

  # Read current model
  CURRENT=$(grep -E '^model: ' "$AGENT_FILE" | sed 's/^model: //')
  echo ""
  echo "── $role ── (current: $CURRENT)"

  if $USE_FZF; then
    SELECTED=$(python3 -c "
import json
with open('/tmp/opencode-gpt-models.json') as f:
    models = json.load(f)
for m in models:
    tags = []
    if m['reasoning']: tags.append('reasoning')
    if m['tool_call']: tags.append('tool_call')
    if m['structured_output']: tags.append('structured')
    ctx = f\"{m['context']//1000}k\" if m['context'] else '?'
    out = f\"{m['output']//1000}k\" if m['output'] else '?'
    print(f\"{m['id']:50s} {m['name']:40s} {','.join(tags):25s} ctx={ctx} out={out}\")
" | fzf --prompt="Model for $role > " --height=25 | awk '{print $1}')

    if [[ -z "$SELECTED" ]]; then
      echo "    → skipped"
      continue
    fi
  else
    echo "  Available GPT models:"
    python3 -c "
import json
with open('/tmp/opencode-gpt-models.json') as f:
    models = json.load(f)
for i, m in enumerate(models, 1):
    tags = []
    if m['reasoning']: tags.append('reasoning')
    if m['tool_call']: tags.append('tool_call')
    if m['structured_output']: tags.append('structured')
    ctx = f\"{m['context']//1000}k\" if m['context'] else '?'
    print(f\"  {i:2d}. {m['id']:45s} [{','.join(tags)}] ctx={ctx}\")
"
    read -p "  Enter number (or 0 to skip): " choice
    if [[ "$choice" -eq 0 || -z "$choice" ]]; then
      echo "    → skipped"
      continue
    fi
    SELECTED=$(python3 -c "
import json
with open('/tmp/opencode-gpt-models.json') as f:
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
  sed -i "s|^model: .*$|model: $SELECTED|" "$AGENT_FILE"
  echo "    ✓ $role → $SELECTED"
done

rm -f /tmp/opencode-gpt-models.json

echo ""
echo "==> ✓ All GPT selections applied."
echo "    Run 'opencode' and select pipeline-gpt to use the new models."
