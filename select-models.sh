#!/usr/bin/env bash
# Interactively assign any OpenCode model to the canonical pipeline roles.
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
AGENTS_DIR="$CONFIG_DIR/agents"
MANIFEST="$CONFIG_DIR/.opencode-pipeline-manifest.json"
ROLES=(pipeline context-manager planner debater implementer reviewer security-reviewer tester linter commit-msg)

if [[ ! -f "$MANIFEST" ]]; then
  echo "Install the canonical pipeline before selecting models." >&2
  exit 1
fi

python3 - "$CONFIG_DIR" "$MANIFEST" <<'PYEOF'
import hashlib
import json
import sys
from pathlib import Path

config_dir = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
with manifest_path.open() as f:
    manifest = json.load(f)
if manifest.get("version") != 3 or not isinstance(manifest.get("files"), dict):
    raise SystemExit("Unsupported pipeline manifest")
for relative, expected_hash in manifest["files"].items():
    path = config_dir / relative
    if not path.exists():
        raise SystemExit(f"Missing installed pipeline file: {path}")
    actual_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual_hash != expected_hash:
        raise SystemExit(f"Refusing to modify changed pipeline file: {path}")
PYEOF

mapfile -t MODELS < <(opencode models)
if [[ ${#MODELS[@]} -eq 0 ]]; then
  echo "No OpenCode models are available." >&2
  exit 1
fi

USE_FZF=false
if command -v fzf &>/dev/null; then
  USE_FZF=true
fi

for role in "${ROLES[@]}"; do
  agent_file="$AGENTS_DIR/$role.md"
  current=$(sed -n 's/^model: //p' "$agent_file")
  echo ""
  echo "-- $role -- (current: $current)"

  if $USE_FZF; then
    selected=$(printf '%s\n' "${MODELS[@]}" | fzf --prompt="Model for $role > " --height=20) || true
    [[ -n "$selected" ]] || continue
  else
    printf '  %2d. %s\n' 0 "keep current"
    for i in "${!MODELS[@]}"; do
      printf '  %2d. %s\n' "$((i + 1))" "${MODELS[$i]}"
    done
    read -r -p "  Enter number: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] || { echo "Invalid choice" >&2; exit 1; }
    [[ "$choice" -ne 0 ]] || continue
    ((choice <= ${#MODELS[@]})) || { echo "Invalid choice" >&2; exit 1; }
    selected="${MODELS[$((choice - 1))]}"
  fi

  python3 - "$agent_file" "$selected" <<'PYEOF'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
model = sys.argv[2]
content = path.read_text()
content, count = re.subn(r"^model:.*$", f"model: {model}", content, count=1, flags=re.MULTILINE)
if count != 1:
    raise SystemExit(f"Missing model field in {path}")
content = re.sub(r"^variant:.*\n", "", content, flags=re.MULTILINE)
path.write_text(content)
PYEOF
  echo "    $role -> $selected"
done

python3 - "$CONFIG_DIR" "$MANIFEST" <<'PYEOF'
import hashlib
import json
import os
import sys
from pathlib import Path

config_dir = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
with manifest_path.open() as f:
    manifest = json.load(f)
if manifest.get("version") != 3 or not isinstance(manifest.get("files"), dict):
    raise SystemExit("Unsupported pipeline manifest")
for relative in list(manifest["files"]):
    path = config_dir / relative
    if path.exists():
        manifest["files"][relative] = hashlib.sha256(path.read_bytes()).hexdigest()
manifest["profile"] = "custom"
temporary = manifest_path.with_suffix(".tmp")
with temporary.open("w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
os.replace(temporary, manifest_path)
PYEOF

echo ""
echo "==> Model selections applied. Restart OpenCode to use them."
