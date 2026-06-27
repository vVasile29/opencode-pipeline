#!/usr/bin/env bash
# auto-select-models.sh — Assigns best free OpenCode Zen models to each pipeline role
# Uses capability scoring from models/roles.json against ~/.cache/opencode/models.json
# Safe to run anytime models change or rate limits are hit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROLES_FILE="$SCRIPT_DIR/models/roles.json"
CACHE_FILE="${HOME}/.cache/opencode/models.json"
AGENTS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/agents"

echo "==> Auto-selecting models for pipeline roles"
echo ""

if [[ ! -f "$CACHE_FILE" ]]; then
  echo "    ✗ models cache not found at $CACHE_FILE"
  echo "    Run 'opencode' once to populate it, or place a models.json there."
  exit 1
fi

if [[ ! -f "$ROLES_FILE" ]]; then
  echo "    ✗ roles.json not found at $ROLES_FILE"
  exit 1
fi

echo "    Scanning free models..."
FREE_MODELS=$(python3 <<'PYEOF' "$CACHE_FILE"
import json, sys

with open(sys.argv[1]) as f:
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
            "id": mid,
            "name": m.get('name', mid),
            "reasoning": m.get('reasoning', False),
            "reasoning_options": m.get('reasoning_options'),
            "tool_call": m.get('tool_call', False),
            "structured_output": m.get('structured_output', False),
            "context": m.get('limit', {}).get('context', 0),
            "output": m.get('limit', {}).get('output', 0),
        })

print(json.dumps({"free": free, "deprecated": deprecated}))
PYEOF
)

MODEL_COUNT=$(echo "$FREE_MODELS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['free']))")
DEP_COUNT=$(echo "$FREE_MODELS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['deprecated'])")
echo "    Found $MODEL_COUNT active free models ($DEP_COUNT deprecated skipped)"

if [[ "$MODEL_COUNT" -lt 3 ]]; then
  echo "    ✗ Fewer than 3 free models available. Pipeline needs at minimum a strong model,"
  echo "      a coder, and a lightweight model. Rethink your provider setup."
  exit 1
fi

# Score each model for each role and assign
python3 <<PYEOF
import json, sys, re, os

data = json.loads('''$FREE_MODELS''')
free_models = data['free']
roles = json.load(open('$ROLES_FILE'))['roles']

def score_model(model, role):
    reqs = role.get('requires', [])
    for req in reqs:
        if req == 'reasoning' and not model.get('reasoning'):
            return -1
        if req == 'tool_call' and not model.get('tool_call'):
            return -1
    
    ctx = model.get('context', 0)
    out = model.get('output', 0)
    
    if ctx < role.get('min_context', 0):
        return -1
    if out < role.get('min_output', 0):
        return -1
    
    prefs = role.get('prefers', {})
    score = 1.0  # base
    
    if prefs.get('reasoning', 0) and model.get('reasoning'):
        bonus = prefs['reasoning'] * 2
        # Always-on reasoning (empty reasoning_options or missing key) gets a bonus
        ropts = model.get('reasoning_options')
        if not ropts or ropts == []:
            bonus += prefs['reasoning']
        score += bonus
    
    if prefs.get('tool_call', 0) and model.get('tool_call'):
        score += prefs['tool_call']
    if prefs.get('structured_output', 0) and model.get('structured_output'):
        score += prefs['structured_output']
    if prefs.get('context', 0):
        # Normalize: 200k context = 1.0 multiplier, up to 2.0 at 1M+
        ctx_factor = min(ctx / 200000, 2.0)
        score += prefs['context'] * ctx_factor
    if prefs.get('output', 0):
        # Normalize: 32k output = 1.0 multiplier, up to 3.0 at 128k+
        out_factor = min(out / 32000, 3.0)
        score += prefs['output'] * out_factor
    
    return score


assigned = {}
role_order = ['planner', 'pipeline', 'debater', 'implementer', 'reviewer', 'tester', 'linter', 'commit-msg']

# Process heavy roles first with scoring, then light roles with smallest-model strategy
heavy_roles = ['planner', 'pipeline', 'debater', 'implementer', 'reviewer']
light_roles = ['tester', 'linter', 'commit-msg']

for role_name in heavy_roles:
    role = roles[role_name]
    best_score = -1
    best_model = None
    
    for m in free_models:
        s = score_model(m, role)
        
        # Enforce perspective diversity
        if role_name in ('debater', 'implementer') and m['id'] == assigned.get('planner'):
            s = -1000
        
        if s > best_score:
            best_score = s
            best_model = m['id']
    
    if best_model:
        assigned[role_name] = best_model

# Lightweight roles: pick smallest model with tool_call, prefer reusing
for role_name in light_roles:
    # Sort by context + output size ascending
    candidates = sorted([m for m in free_models if m.get('tool_call')], key=lambda m: m.get('context', 0) + m.get('output', 0))
    
    best_model = None
    for m in candidates:
        # Prefer models already assigned to another light role (reuse)
        if m['id'] in [assigned.get(r) for r in light_roles if r != role_name]:
            best_model = m['id']
            break
    
    if not best_model:
        # Fall back to smallest model overall
        for m in candidates:
            best_model = m['id']
            break
    
    if best_model:
        assigned[role_name] = best_model


print("## Model Assignments")
print()
for role_name in role_order:
    if role_name in assigned:
        mid = assigned[role_name]
        mname = next((m['name'] for m in free_models if m['id'] == mid), mid)
        print(f"  {role_name:15s} → opencode/{mid:40s} ({mname})")
    else:
        print(f"  {role_name:15s} → ⚠ NO SUITABLE MODEL")

print()
print("==> Updating agent files...")
for role_name, model_id in assigned.items():
    agent_path = os.path.join('$AGENTS_DIR', f'{role_name}.md')
    if not os.path.exists(agent_path):
        print(f"    ⚠ {role_name}.md not found — skipping")
        continue
    
    with open(agent_path) as f:
        content = f.read()
    
    new_content = re.sub(
        r'^(model:\s*)opencode/\S+',
        rf'\1opencode/{model_id}',
        content,
        count=1,
        flags=re.MULTILINE
    )
    
    if new_content != content:
        with open(agent_path, 'w') as f:
            f.write(new_content)
        print(f"    ✓ {role_name}.md → opencode/{model_id}")
    else:
        print(f"    - {role_name}.md (pattern not matched — unchanged)")

print()
print("==> ✓ All models assigned. Agent files updated.")
print("    Run 'opencode' to use the new models.")
PYEOF
