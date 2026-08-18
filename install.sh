#!/usr/bin/env bash
# Install or switch the canonical OpenCode pipeline model profile.
# Usage: install.sh [profile]
set -euo pipefail

PROFILE="${1:-free}"
REPO_URL="${OPENCODE_PIPELINE_REPO_URL:-https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
AGENTS_DIR="$CONFIG_DIR/agents"
PLUGINS_DIR="$CONFIG_DIR/plugins"
MANIFEST="$CONFIG_DIR/.opencode-pipeline-manifest.json"
LEGACY_GPT_MANIFEST="$CONFIG_DIR/.opencode-pipeline-gpt-manifest.json"
ROLES=(pipeline planner debater implementer reviewer security-reviewer tester linter commit-msg)

if [[ ! "$PROFILE" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "Invalid profile name: $PROFILE" >&2
  exit 1
fi

if [[ -f "$LEGACY_GPT_MANIFEST" ]]; then
  echo "A legacy pipeline-gpt installation is still present." >&2
  echo "Uninstall it before switching to the canonical pipeline." >&2
  exit 1
fi

STAGE_DIR=$(mktemp -d)
trap 'rm -rf "$STAGE_DIR"' EXIT
mkdir -p "$STAGE_DIR/agents"

echo "==> Downloading canonical pipeline agents"
for role in "${ROLES[@]}"; do
  curl -fsSL "$REPO_URL/agents/$role.md" -o "$STAGE_DIR/agents/$role.md"
done
curl -fsSL "$REPO_URL/models/profiles/$PROFILE.json" -o "$STAGE_DIR/profile.json"
curl -fsSL "$REPO_URL/plugins/opencode-pipeline-permissions.js" -o "$STAGE_DIR/permissions.js"

python3 - "$STAGE_DIR" <<'PYEOF'
import json
import re
import sys
from pathlib import Path

stage = Path(sys.argv[1])
roles = (
    "pipeline", "planner", "debater", "implementer", "reviewer",
    "security-reviewer", "tester", "linter", "commit-msg",
)

with (stage / "profile.json").open() as f:
    profile = json.load(f)

agents = profile.get("agents")
if not isinstance(agents, dict) or set(agents) != set(roles):
    raise SystemExit("Profile must define exactly the nine canonical pipeline agents")

for role in roles:
    settings = agents[role]
    model = settings.get("model") if isinstance(settings, dict) else None
    variant = settings.get("variant") if isinstance(settings, dict) else None
    if not isinstance(model, str) or not re.fullmatch(r"[A-Za-z0-9._:/-]+", model):
        raise SystemExit(f"Invalid model for {role}: {model!r}")
    if variant is not None and (not isinstance(variant, str) or not re.fullmatch(r"[A-Za-z0-9._-]+", variant)):
        raise SystemExit(f"Invalid variant for {role}: {variant!r}")

    path = stage / "agents" / f"{role}.md"
    content = path.read_text()
    content, count = re.subn(r"^model:.*$", f"model: {model}", content, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"Missing model field in {role}.md")
    content = re.sub(r"^variant:.*\n", "", content, flags=re.MULTILINE)
    if variant:
        content = re.sub(r"^(model:.*)$", rf"\1\nvariant: {variant}", content, count=1, flags=re.MULTILINE)
    path.write_text(content)
PYEOF

python3 - "$CONFIG_DIR" "$MANIFEST" <<'PYEOF'
import hashlib
import json
import sys
from pathlib import Path

config_dir = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
targets = [f"agents/{role}.md" for role in (
    "pipeline", "planner", "debater", "implementer", "reviewer",
    "security-reviewer", "tester", "linter", "commit-msg",
)] + ["plugins/opencode-pipeline-permissions.js"]

owned = {}
if manifest_path.exists():
    with manifest_path.open() as f:
        manifest = json.load(f)
    if manifest.get("version") != 3 or not isinstance(manifest.get("files"), dict):
        raise SystemExit(
            "A legacy pipeline installation is present. Run its matching uninstaller before upgrading."
        )
    owned = manifest["files"]

for relative in targets:
    path = config_dir / relative
    if not path.exists():
        continue
    expected = owned.get(relative)
    if expected is None:
        raise SystemExit(f"Refusing to overwrite unowned file: {path}")
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit(f"Refusing to overwrite modified pipeline file: {path}")
PYEOF

mkdir -p "$AGENTS_DIR" "$PLUGINS_DIR"
for role in "${ROLES[@]}"; do
  install -m 0644 "$STAGE_DIR/agents/$role.md" "$AGENTS_DIR/$role.md"
done
install -m 0644 "$STAGE_DIR/permissions.js" "$PLUGINS_DIR/opencode-pipeline-permissions.js"

python3 - "$CONFIG_DIR" "$MANIFEST" "$PROFILE" <<'PYEOF'
import datetime
import hashlib
import json
import os
import sys
from pathlib import Path

config_dir = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
profile = sys.argv[3]
files = [f"agents/{role}.md" for role in (
    "pipeline", "planner", "debater", "implementer", "reviewer",
    "security-reviewer", "tester", "linter", "commit-msg",
)] + ["plugins/opencode-pipeline-permissions.js"]

manifest = {
    "version": 3,
    "profile": profile,
    "installed_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "files": {
        relative: hashlib.sha256((config_dir / relative).read_bytes()).hexdigest()
        for relative in files
    },
}
temporary = manifest_path.with_suffix(".tmp")
with temporary.open("w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
os.replace(temporary, manifest_path)
PYEOF

echo "==> Pipeline installed with the '$PROFILE' profile"
echo "    Restart OpenCode, press Tab, and select 'pipeline'."
echo "    Re-run this installer with another profile to switch models."
