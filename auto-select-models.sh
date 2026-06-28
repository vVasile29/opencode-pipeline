#!/usr/bin/env bash
# auto-select-models.sh — Assigns best free OpenCode Zen models to each pipeline role
# Uses capability scoring from models/roles.json against ~/.cache/opencode/models.json
# Safe to run anytime models change.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROLES_FILE="$SCRIPT_DIR/models/roles.json"
CACHE_FILE="${HOME}/.cache/opencode/models.json"
AGENTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/agents"

echo "==> Auto-selecting models for pipeline roles"
echo ""

if [[ ! -f "$CACHE_FILE" ]]; then
  echo "    \u2717 models cache not found at $CACHE_FILE"
  echo "    Run 'opencode' once to populate it, or place a models.json there."
  exit 1
fi

if [[ ! -f "$ROLES_FILE" ]]; then
  echo "    \u2717 roles.json not found at $ROLES_FILE"
  exit 1
fi

echo "    Scanning free models..."
FREE_MODELS=$(python3 -c "
import json

with open('$CACHE_FILE') as f:
    data = json.load(f)

opencode = data.get('opencode', {})
models = opencode.get('models', {})

free = []
deprecated = 0
for mid, m in models.items():
    if not isinstance(m, dict):
        continue
    cost = m.get('cost', {})
    status = m.get('status', '')
    if isinstance(cost, dict) and cost.get('input', 1) == 0:
        if status == 'deprecated':
            deprecated += 1
            continue
        free.append({
            'id': mid,
            'name': m.get('name', mid),
            'reasoning': m.get('reasoning', False),
            'reasoning_options': m.get('reasoning_options'),
            'tool_call': m.get('tool_call', False),
            'structured_output': m.get('structured_output', False),
            'context': m.get('limit', {}).get('context', 0),
            'output': m.get('limit', {}).get('output', 0),
        })

print(json.dumps({'free': free, 'deprecated': deprecated}))")

MODEL_COUNT=$(echo "$FREE_MODELS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['free']))")
DEP_COUNT=$(echo "$FREE_MODELS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['deprecated'])")
echo "    Found $MODEL_COUNT active free models ($DEP_COUNT deprecated skipped)"

if [[ "$MODEL_COUNT" -lt 3 ]]; then
  echo "    \u2717 Fewer than 3 free models available. Pipeline needs at minimum a strong model,"
  echo "      a coder, and a lightweight model. Rethink your provider setup."
  exit 1
fi

FREE_MODELS_FILE=$(mktemp /tmp/opencode-free-models-XXXX.json)
echo "$FREE_MODELS" > "$FREE_MODELS_FILE"

python3 "$SCRIPT_DIR/models/assign_models.py" "$FREE_MODELS_FILE" "$ROLES_FILE" "$AGENTS_DIR"

rm -f "$FREE_MODELS_FILE"
