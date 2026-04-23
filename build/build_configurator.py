#!/usr/bin/env python3
"""
Reads templates/ + configurator_template.html and produces a self-contained configurator.html.

Imports MODULES and FORM_SCHEMA from config_schema.py (shared with configure.py).
Paths are resolved relative to this script, so it works after `git clone` anywhere.

Usage (from repo root or anywhere):
    python3 build/build_configurator.py
"""
import base64
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))
from config_schema import MODULES, FORM_SCHEMA, target_path_for  # noqa: E402

TEMPLATE_DIR = REPO_ROOT / "templates"
OUTPUT_HTML = REPO_ROOT / "configurator.html"
HTML_TEMPLATE_PATH = REPO_ROOT / "build" / "configurator_template.html"


def read_b64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("ascii")


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def build_modules_data():
    modules = []
    for m in MODULES:
        files = []
        for rel in m["paths"]:
            target = target_path_for(rel)
            if not target:
                continue
            files.append({
                "target": target,
                "source": rel,
                "executable": rel.endswith(".sh"),
                "contentB64": read_b64(TEMPLATE_DIR / rel),
            })

        entry = {
            "id": m["id"],
            "title": m["title"],
            "description": m["description"],
            "required": m.get("required", False),
            "files": files,
        }
        if "gitignoreSource" in m:
            entry["gitignoreLines"] = (
                (TEMPLATE_DIR / m["gitignoreSource"]).read_text(encoding="utf-8").splitlines()
            )
        if m.get("settingsPatch"):
            patch = read_json(TEMPLATE_DIR / m["settingsPatch"])
            patch = {k: v for k, v in patch.items() if not k.startswith("//")}
            entry["settingsPatch"] = patch
        if "extraSettingsHook" in m:
            entry["extraSettingsHook"] = m["extraSettingsHook"]
        if "extraSettings" in m:
            entry["extraSettings"] = m["extraSettings"]
        modules.append(entry)
    return modules


def main():
    modules = build_modules_data()
    base_settings = read_json(TEMPLATE_DIR / "core/dot-claude/settings.json")
    data = {
        "modules": modules,
        "baseSettings": base_settings,
        "formSchema": FORM_SCHEMA,
    }
    data_json = json.dumps(data)
    data_b64 = base64.b64encode(data_json.encode("utf-8")).decode("ascii")
    html = HTML_TEMPLATE_PATH.read_text(encoding="utf-8").replace("__DATA_B64__", data_b64)
    OUTPUT_HTML.write_text(html, encoding="utf-8")
    print(f"Wrote {OUTPUT_HTML} ({len(html):,} chars, {len(data_b64):,} chars data)")


if __name__ == "__main__":
    main()
