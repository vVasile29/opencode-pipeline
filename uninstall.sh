#!/usr/bin/env bash
# Remove files owned by the canonical OpenCode pipeline installation.
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
MANIFEST="$CONFIG_DIR/.opencode-pipeline-manifest.json"

if [[ ! -f "$MANIFEST" ]]; then
  echo "No canonical pipeline manifest found; nothing to uninstall."
  exit 0
fi

python3 - "$CONFIG_DIR" "$MANIFEST" <<'PYEOF'
import hashlib
import json
import sys
from pathlib import Path

config_dir = Path(sys.argv[1]).resolve()
manifest_path = Path(sys.argv[2])
with manifest_path.open() as f:
    manifest = json.load(f)

if manifest.get("version") != 3 or not isinstance(manifest.get("files"), dict):
    raise SystemExit("Legacy manifest detected; use the legacy uninstaller for that installation")

preserved = []
for relative, expected_hash in manifest["files"].items():
    if not isinstance(relative, str) or not isinstance(expected_hash, str):
        raise SystemExit("Invalid pipeline manifest")
    relative_path = Path(relative)
    if len(relative_path.parts) != 2 or relative_path.parts[0] not in {"agents", "plugins"}:
        raise SystemExit(f"Unsafe manifest path: {relative}")
    path = (config_dir / relative).resolve()
    if config_dir not in path.parents:
        raise SystemExit(f"Unsafe manifest path: {relative}")
    if not path.exists():
        continue
    actual_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual_hash != expected_hash:
        preserved.append(path)
        continue
    path.unlink()
    print(f"removed {path}")

manifest_path.unlink()
for path in preserved:
    print(f"preserved modified file: {path}")
PYEOF

echo "==> Pipeline uninstalled"
echo "    Restart OpenCode to unload the pipeline and permission plugin."
