#!/usr/bin/env python3
"""Assign the best free model to each pipeline role.

Usage:
  assign_models.py <free_models.json> <roles.json> <agents_dir> [--rankings <out.json>]
"""
import json
import os
import re
import sys


def score_model(model, role):
    for req in role.get("requires", []):
        if req == "reasoning" and not model.get("reasoning"):
            return -1
        if req == "tool_call" and not model.get("tool_call"):
            return -1

    ctx = model.get("context", 0)
    out = model.get("output", 0)

    if ctx < role.get("min_context", 0):
        return -1
    if out < role.get("min_output", 0):
        return -1

    prefs = role.get("prefers", {})
    score = 1.0

    if prefs.get("reasoning", 0) and model.get("reasoning"):
        bonus = prefs["reasoning"] * 2
        ropts = model.get("reasoning_options")
        if not ropts or ropts == []:
            bonus += prefs["reasoning"]
        score += bonus

    if prefs.get("tool_call", 0) and model.get("tool_call"):
        score += prefs["tool_call"]
    if prefs.get("structured_output", 0) and model.get("structured_output"):
        score += prefs["structured_output"]
    if prefs.get("context", 0):
        score += prefs["context"] * min(ctx / 200000, 2.0)
    if prefs.get("output", 0):
        score += prefs["output"] * min(out / 32000, 3.0)

    return score


def build_rankings(free_models, roles):
    """Return (rankings_dict, assigned_dict)."""
    heavy_roles = ["planner", "pipeline", "debater", "implementer", "reviewer"]
    light_roles = ["tester", "linter", "commit-msg"]

    assigned = {}
    rankings = {}

    for role_name in heavy_roles:
        role = roles[role_name]
        scored = []
        for m in free_models:
            s = score_model(m, role)
            if s >= 0:
                scored.append((s, m["id"]))
        scored.sort(key=lambda x: (-x[0], x[1]))
        rankings[role_name] = [mid for _, mid in scored]

        for s, mid in scored:
            if role_name in ("debater", "implementer") and mid == assigned.get("planner"):
                continue
            assigned[role_name] = mid
            break

    for role_name in light_roles:
        role = roles[role_name]
        candidates = sorted(
            [m for m in free_models if m.get("tool_call")],
            key=lambda m: m.get("context", 0) + m.get("output", 0),
        )
        scored = []
        for m in candidates:
            s = score_model(m, role)
            if s >= 0:
                scored.append((m.get("context", 0) + m.get("output", 0), m["id"]))
        scored.sort(key=lambda x: (x[0], x[1]))
        rankings[role_name] = [mid for _, mid in scored]

        best_model = None
        for m in candidates:
            if m["id"] in [assigned.get(r) for r in light_roles if r != role_name]:
                best_model = m["id"]
                break
        if not best_model and candidates:
            best_model = candidates[0]["id"]
        if best_model:
            assigned[role_name] = best_model

    return rankings, assigned


def update_agent_files(agents_dir, assigned):
    updated = []
    for role_name, model_id in assigned.items():
        agent_path = os.path.join(agents_dir, f"{role_name}.md")
        if not os.path.exists(agent_path):
            continue
        with open(agent_path) as f:
            content = f.read()
        new_content = re.sub(
            r"^(model:\s*)opencode/\S+",
            rf"\1opencode/{model_id}",
            content,
            count=1,
            flags=re.MULTILINE,
        )
        if new_content != content:
            with open(agent_path, "w") as f:
                f.write(new_content)
            updated.append((role_name, model_id))
    return updated


def main():
    rankings_path = None
    filtered = []
    i = 1
    while i < len(sys.argv):
        a = sys.argv[i]
        if a == "--rankings" and i + 1 < len(sys.argv):
            rankings_path = sys.argv[i + 1]
            i += 2
        else:
            filtered.append(a)
            i += 1

    if len(filtered) < 3:
        print("Usage: assign_models.py [--rankings <out.json>] <free_models.json> <roles.json> <agents_dir>",
              file=sys.stderr)
        sys.exit(1)

    models_file, roles_file, agents_dir = filtered[0], filtered[1], filtered[2]

    with open(models_file) as f:
        free_models = json.load(f)["free"]
    with open(roles_file) as f:
        roles = json.load(f)["roles"]

    rankings, assigned = build_rankings(free_models, roles)

    if rankings_path:
        with open(rankings_path, "w") as f:
            json.dump(rankings, f, indent=2)

    role_order = ["planner", "pipeline", "debater", "implementer", "reviewer", "tester", "linter", "commit-msg"]
    print("## Model Assignments\n")
    for role_name in role_order:
        mid = assigned.get(role_name)
        if mid:
            mname = next((m["name"] for m in free_models if m["id"] == mid), mid)
            print(f"  {role_name:15s} \u2192 opencode/{mid:40s} ({mname})")
        else:
            print(f"  {role_name:15s} \u2192 \u26a0 NO MODEL")

    print("\n==> Updating agent files...")
    updated = update_agent_files(agents_dir, assigned)
    for role_name, model_id in updated:
        print(f"    \u2713 {role_name}.md \u2192 opencode/{model_id}")
    if not updated:
        print("    (no changes)")

    print("\n==> \u2713 All models assigned. Agent files updated.")
    print("    Run 'opencode' to use the new models.")


if __name__ == "__main__":
    main()
