#!/usr/bin/env bash
# Assign any OpenCode model to pipeline roles without modifying agent definitions.
# Usage: select-models.sh [model]
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
MANIFEST="$CONFIG_DIR/.opencode-pipeline-manifest.json"
ACTIVE_PROFILE="$CONFIG_DIR/.opencode-pipeline-profile.json"
ROLES=(pipeline context-manager planner debater implementer reviewer security-reviewer tester linter commit-msg)
MODEL="${1:-}"

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [model]" >&2
  exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "Install the canonical pipeline before selecting models." >&2
  exit 1
fi

python3 - "$MANIFEST" "$ACTIVE_PROFILE" <<'PYEOF'
import hashlib
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
profile_path = Path(sys.argv[2])
if manifest_path.is_symlink() or not manifest_path.is_file():
    raise SystemExit(f"Invalid pipeline manifest: {manifest_path}")
with manifest_path.open() as stream:
    manifest = json.load(stream)
if manifest.get("version") != 4 or not isinstance(manifest.get("files"), dict):
    raise SystemExit("Upgrade the pipeline installation before selecting models")
expected = manifest["files"].get(".opencode-pipeline-profile.json")
if not isinstance(expected, str):
    raise SystemExit("Installed profile is not owned by the pipeline manifest")
if profile_path.is_symlink() or not profile_path.is_file():
    raise SystemExit(f"Missing installed pipeline profile: {profile_path}")
actual = hashlib.sha256(profile_path.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f"Refusing to overwrite modified pipeline profile: {profile_path}")
PYEOF

mapfile -t MODELS < <(opencode models)
if [[ ${#MODELS[@]} -eq 0 ]]; then
  echo "No OpenCode models are available." >&2
  exit 1
fi

if [[ -n "$MODEL" ]] && ! printf '%s\n' "${MODELS[@]}" | grep -Fxq -- "$MODEL"; then
  echo "Model is not available in OpenCode: $MODEL" >&2
  exit 1
fi

USE_FZF=false
if command -v fzf &>/dev/null; then
  USE_FZF=true
fi

declare -A SELECTIONS=()
for role in "${ROLES[@]}"; do
  current=$(python3 - "$ACTIVE_PROFILE" "$role" <<'PYEOF'
import json
import sys
from pathlib import Path

with Path(sys.argv[1]).open() as stream:
    print(json.load(stream)["agents"][sys.argv[2]]["model"])
PYEOF
)
  if [[ -n "$MODEL" ]]; then
    selected="$MODEL"
  else
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
  fi

  SELECTIONS["$role"]="$selected"
  echo "    $role -> $selected"
done

if [[ ${#SELECTIONS[@]} -eq 0 ]]; then
  echo ""
  echo "==> No model selections changed."
  exit 0
fi

SELECTION_ARGS=()
for role in "${ROLES[@]}"; do
  if [[ -n "${SELECTIONS[$role]+set}" ]]; then
    SELECTION_ARGS+=("$role" "${SELECTIONS[$role]}")
  fi
done

python3 - "$CONFIG_DIR" "$MANIFEST" "$ACTIVE_PROFILE" "${SELECTION_ARGS[@]}" <<'PYEOF'
import hashlib
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

config_dir = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
profile_path = Path(sys.argv[3])
selections = dict(zip(sys.argv[4::2], sys.argv[5::2]))
relative = ".opencode-pipeline-profile.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


with manifest_path.open() as stream:
    manifest = json.load(stream)
if manifest.get("version") != 4 or not isinstance(manifest.get("files"), dict):
    raise SystemExit("Unsupported pipeline manifest")
expected = manifest["files"].get(relative)
if not isinstance(expected, str) or digest(profile_path) != expected:
    raise SystemExit(f"Refusing to overwrite modified pipeline profile: {profile_path}")
with profile_path.open() as stream:
    profile = json.load(stream)

for role, model in selections.items():
    settings = profile["agents"][role]
    settings["model"] = model
    settings.pop("variant", None)
profile["name"] = "custom"
profile["description"] = "Custom OpenCode Pipeline model selections"


def destination_temp(prefix):
    descriptor, name = tempfile.mkstemp(prefix=prefix, dir=config_dir)
    os.close(descriptor)
    return Path(name)


profile_new = destination_temp(".opencode-pipeline-profile-new-")
profile_old = destination_temp(".opencode-pipeline-profile-old-")
manifest_new = destination_temp(".opencode-pipeline-manifest-new-")
manifest_old = destination_temp(".opencode-pipeline-manifest-old-")
temporary = {profile_new, profile_old, manifest_new, manifest_old}
profile_replaced = False
manifest_replaced = False
try:
    with profile_new.open("w") as stream:
        json.dump(profile, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(profile_new, 0o644)
    manifest["profile"] = "custom"
    manifest["files"][relative] = digest(profile_new)
    with manifest_new.open("w") as stream:
        json.dump(manifest, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(manifest_new, 0o644)
    shutil.copy2(profile_path, profile_old)
    shutil.copy2(manifest_path, manifest_old)

    os.replace(profile_new, profile_path)
    temporary.discard(profile_new)
    profile_replaced = True
    os.replace(manifest_new, manifest_path)
    temporary.discard(manifest_new)
    manifest_replaced = True
except BaseException:
    if manifest_replaced:
        os.replace(manifest_old, manifest_path)
        temporary.discard(manifest_old)
    if profile_replaced:
        os.replace(profile_old, profile_path)
        temporary.discard(profile_old)
    raise
finally:
    for path in temporary:
        path.unlink(missing_ok=True)
PYEOF

echo ""
echo "==> Model selections applied to the active profile."
echo "    Agent definitions were not modified. Restart OpenCode to use them."
