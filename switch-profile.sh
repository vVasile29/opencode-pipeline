#!/usr/bin/env bash
# Switch only the model profile used by an installed OpenCode pipeline.
# Usage: switch-profile.sh <profile>
set -euo pipefail

PROFILE="${1:-}"
REPO_URL="${OPENCODE_PIPELINE_REPO_URL:-https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
MANIFEST="$CONFIG_DIR/.opencode-pipeline-manifest.json"

if [[ $# -ne 1 || ! "$PROFILE" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "Usage: $0 <profile>" >&2
  exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "Install the canonical pipeline before switching profiles." >&2
  exit 1
fi

STAGE_DIR=$(mktemp -d)
trap 'rm -rf "$STAGE_DIR"' EXIT
curl -fsSL "$REPO_URL/models/profiles/$PROFILE.json" -o "$STAGE_DIR/profile.json"

python3 - "$STAGE_DIR/profile.json" "$CONFIG_DIR" "$MANIFEST" "$PROFILE" <<'PYEOF'
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

source = Path(sys.argv[1])
config_dir = Path(sys.argv[2])
manifest_path = Path(sys.argv[3])
profile_name = sys.argv[4]
relative = ".opencode-pipeline-profile.json"
target = config_dir / relative
roles = {
    "pipeline", "context-manager", "planner", "debater", "implementer",
    "reviewer", "security-reviewer", "tester", "linter", "commit-msg",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def regular_file(path, label):
    if path.is_symlink() or not path.is_file():
        raise RuntimeError(f"{label} is not a regular file: {path}")


regular_file(source, "Downloaded profile")
with source.open() as stream:
    profile = json.load(stream)
if profile.get("name") != profile_name:
    raise RuntimeError("Downloaded profile name does not match the requested profile")
agents = profile.get("agents")
if not isinstance(agents, dict) or set(agents) != roles:
    raise RuntimeError("Profile must define exactly the canonical pipeline agents")
for role, settings in agents.items():
    model = settings.get("model") if isinstance(settings, dict) else None
    variant = settings.get("variant") if isinstance(settings, dict) else None
    if not isinstance(model, str) or not re.fullmatch(r"[A-Za-z0-9._:/-]+", model):
        raise RuntimeError(f"Invalid model for {role}: {model!r}")
    if variant is not None and (
        not isinstance(variant, str) or not re.fullmatch(r"[A-Za-z0-9._-]+", variant)
    ):
        raise RuntimeError(f"Invalid variant for {role}: {variant!r}")

regular_file(manifest_path, "Manifest")
with manifest_path.open() as stream:
    manifest = json.load(stream)
if manifest.get("version") != 4 or not isinstance(manifest.get("files"), dict):
    raise RuntimeError("Upgrade the pipeline installation before switching profiles")
expected = manifest["files"].get(relative)
if not isinstance(expected, str):
    raise RuntimeError("Installed profile is not owned by the pipeline manifest")
regular_file(target, "Installed profile")
if digest(target) != expected:
    raise RuntimeError(f"Refusing to overwrite modified pipeline profile: {target}")

manifest["profile"] = profile_name
manifest["files"][relative] = digest(source)


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
    shutil.copyfile(source, profile_new)
    os.chmod(profile_new, 0o644)
    shutil.copy2(target, profile_old)
    shutil.copy2(manifest_path, manifest_old)
    with manifest_new.open("w") as stream:
        json.dump(manifest, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(manifest_new, 0o644)

    os.replace(profile_new, target)
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
        os.replace(profile_old, target)
        temporary.discard(profile_old)
    raise
finally:
    for path in temporary:
        path.unlink(missing_ok=True)
PYEOF

echo "==> Pipeline profile switched to '$PROFILE'"
echo "    Agent definitions were not modified. Restart OpenCode to use the profile."
