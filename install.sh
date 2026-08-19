#!/usr/bin/env bash
# Install or upgrade the canonical OpenCode pipeline and select an initial profile.
# Usage: install.sh [profile]
set -euo pipefail

PROFILE="${1:-free}"
REPO_URL="${OPENCODE_PIPELINE_REPO_URL:-https://raw.githubusercontent.com/vVasile29/opencode-pipeline/master}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
MANIFEST="$CONFIG_DIR/.opencode-pipeline-manifest.json"
LEGACY_GPT_MANIFEST="$CONFIG_DIR/.opencode-pipeline-gpt-manifest.json"
ROLES=(pipeline context-manager planner debater implementer reviewer security-reviewer tester linter commit-msg)

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

python3 - "$STAGE_DIR" "$PROFILE" <<'PYEOF'
import json
import re
import sys
from pathlib import Path

stage = Path(sys.argv[1])
profile_name = sys.argv[2]
roles = (
    "pipeline", "context-manager", "planner", "debater", "implementer", "reviewer",
    "security-reviewer", "tester", "linter", "commit-msg",
)

with (stage / "profile.json").open() as f:
    profile = json.load(f)
if profile.get("name") != profile_name:
    raise SystemExit("Downloaded profile name does not match the requested profile")

agents = profile.get("agents")
if not isinstance(agents, dict) or set(agents) != set(roles):
    raise SystemExit("Profile must define exactly the ten canonical pipeline agents")

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
    if re.search(r"^(model|variant):", content, flags=re.MULTILINE):
        raise SystemExit(f"Canonical agent must not define model or variant: {role}.md")
PYEOF

python3 - "$STAGE_DIR" "$CONFIG_DIR" "$MANIFEST" "$PROFILE" <<'PYEOF'
import datetime
import hashlib
import json
import os
import shutil
import signal
import sys
import tempfile
from pathlib import Path

stage_dir = Path(sys.argv[1])
config_dir = Path(sys.argv[2])
manifest_path = Path(sys.argv[3])
profile = sys.argv[4]
roles = (
    "pipeline", "context-manager", "planner", "debater", "implementer", "reviewer",
    "security-reviewer", "tester", "linter", "commit-msg",
)
sources = {
    **{f"agents/{role}.md": stage_dir / "agents" / f"{role}.md" for role in roles},
    "plugins/opencode-pipeline-permissions.js": stage_dir / "permissions.js",
    ".opencode-pipeline-profile.json": stage_dir / "profile.json",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def regular_file(path, label):
    if path.is_symlink() or not path.is_file():
        raise RuntimeError(f"{label} is not a regular file: {path}")


for relative, source in sources.items():
    regular_file(source, "Staged file")
    if source.stat().st_size == 0:
        raise RuntimeError(f"Staged file is empty: {source}")

owned = {}
if manifest_path.is_symlink():
    raise RuntimeError(f"Refusing manifest symlink: {manifest_path}")
if manifest_path.exists():
    regular_file(manifest_path, "Manifest")
    with manifest_path.open() as f:
        previous_manifest = json.load(f)
    if previous_manifest.get("version") not in {3, 4} or not isinstance(previous_manifest.get("files"), dict):
        raise RuntimeError("Unsupported pipeline manifest")
    owned = previous_manifest["files"]

for relative in sources:
    target = config_dir / relative
    parent = target.parent
    if parent.is_symlink() or parent.exists() and not parent.is_dir():
        raise RuntimeError(f"Refusing non-directory target parent: {parent}")
    if target.is_symlink():
        raise RuntimeError(f"Refusing target symlink: {target}")
    if not target.exists():
        continue
    regular_file(target, "Installed target")
    expected = owned.get(relative)
    if expected is None:
        raise RuntimeError(f"Refusing to overwrite unowned file: {target}")
    if digest(target) != expected:
        raise RuntimeError(f"Refusing to overwrite modified pipeline file: {target}")

config_dir.mkdir(parents=True, exist_ok=True)
for relative in sources:
    (config_dir / relative).parent.mkdir(parents=True, exist_ok=True)

new_manifest = {
    "version": 4,
    "profile": profile,
    "installed_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "files": {relative: digest(source) for relative, source in sources.items()},
}

new_files = {}
backups = {}
temporary_paths = set()
replaced = []
manifest_replaced = False
manifest_backup = None


def destination_temp(parent, prefix):
    descriptor, name = tempfile.mkstemp(prefix=prefix, dir=parent)
    os.close(descriptor)
    path = Path(name)
    temporary_paths.add(path)
    return path


def durable_copy(source, destination):
    shutil.copyfile(source, destination)
    os.chmod(destination, 0o644)
    with destination.open("rb") as stream:
        os.fsync(stream.fileno())


def rollback():
    if manifest_replaced:
        if manifest_backup is None:
            manifest_path.unlink(missing_ok=True)
        else:
            os.replace(manifest_backup, manifest_path)
            temporary_paths.discard(manifest_backup)
    for relative in reversed(replaced):
        target = config_dir / relative
        backup = backups[relative]
        if backup is None:
            target.unlink(missing_ok=True)
        else:
            os.replace(backup, target)
            temporary_paths.discard(backup)


def interrupt(signum, _frame):
    raise InterruptedError(f"Installation interrupted by signal {signum}")


previous_handlers = {
    signal.SIGINT: signal.getsignal(signal.SIGINT),
    signal.SIGTERM: signal.getsignal(signal.SIGTERM),
}
failure_after = int(os.environ.get("OPENCODE_PIPELINE_FAIL_AFTER_REPLACE", "0"))
replacement_count = 0

signal.signal(signal.SIGINT, interrupt)
signal.signal(signal.SIGTERM, interrupt)

try:
    for relative, source in sources.items():
        target = config_dir / relative
        new_file = destination_temp(target.parent, ".opencode-pipeline-new-")
        durable_copy(source, new_file)
        new_files[relative] = new_file
        if target.exists():
            backup = destination_temp(target.parent, ".opencode-pipeline-old-")
            shutil.copy2(target, backup)
            backups[relative] = backup
        else:
            backups[relative] = None

    manifest_new = destination_temp(config_dir, ".opencode-pipeline-manifest-new-")
    with manifest_new.open("w") as f:
        json.dump(new_manifest, f, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.chmod(manifest_new, 0o644)
    if manifest_path.exists():
        manifest_backup = destination_temp(config_dir, ".opencode-pipeline-manifest-old-")
        shutil.copy2(manifest_path, manifest_backup)

    for relative in sources:
        target = config_dir / relative
        replaced.append(relative)
        os.replace(new_files[relative], target)
        temporary_paths.discard(new_files[relative])
        replacement_count += 1
        if failure_after == replacement_count:
            raise RuntimeError(f"Injected failure after replacement {replacement_count}")

    manifest_replaced = True
    os.replace(manifest_new, manifest_path)
    temporary_paths.discard(manifest_new)
    replacement_count += 1
    if failure_after == replacement_count:
        raise RuntimeError(f"Injected failure after replacement {replacement_count}")
except BaseException:
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    rollback()
    raise
finally:
    for current_signal, handler in previous_handlers.items():
        signal.signal(current_signal, handler)
    for path in temporary_paths:
        path.unlink(missing_ok=True)
PYEOF

echo "==> Pipeline installed with the '$PROFILE' profile"
echo "    Restart OpenCode, press Tab, and select 'pipeline'."
echo "    Use switch-profile.sh to change models without reinstalling agents."
