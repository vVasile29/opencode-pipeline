#!/usr/bin/env bash
# auto-select-models.sh — Assigns best free OpenCode Zen models to each pipeline role
# Uses capability scoring from models/roles.json against ~/.cache/opencode/models.json
# Safe to run anytime models change or rate limits are hit.
#
# Options:
#   --state-file <path>   Also write fallback rankings state to <path>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROLES_FILE="$SCRIPT_DIR/models/roles.json"
CACHE_FILE="${HOME}/.cache/opencode/models.json"
AGENTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/agents"

STATE_FILE=""
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--state-file" ]]; then
    STATE_FILE="--state-file"
  elif [[ -n "$STATE_FILE" && "$STATE_FILE" == "--state-file" ]]; then
    STATE_FILE="$arg"
  else
    ARGS+=("$arg")
  fi
done

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

# Build args for assign_models.py
PY_ARGS=()
PY_ARGS+=("$FREE_MODELS_FILE" "$ROLES_FILE" "$AGENTS_DIR")

RANKINGS_FILE=""
if [[ -n "$STATE_FILE" ]]; then
  RANKINGS_FILE=$(mktemp /tmp/opencode-rankings-XXXX.json)
  PY_ARGS+=("--rankings" "$RANKINGS_FILE")
fi

python3 "$SCRIPT_DIR/models/assign_models.py" "${PY_ARGS[@]}"

# If we generated rankings, wrap into state file with tier info
if [[ -n "$STATE_FILE" && -n "$RANKINGS_FILE" ]]; then
  python3 -c "
import json

with open('$RANKINGS_FILE') as f:
    rankings = json.load(f)

max_tier = max(len(v) - 1 for v in rankings.values()) if rankings else 0

state = {
    'version': 1,
    'tier': 0,
    'max_tier': max_tier,
    'rankings': rankings,
}

with open('$STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
print(f'    \u2713 Fallback state saved ({len(rankings)} roles, {max_tier} fallback tiers)')
"
  rm -f "$RANKINGS_FILE"
fi

rm -f "$FREE_MODELS_FILE"
