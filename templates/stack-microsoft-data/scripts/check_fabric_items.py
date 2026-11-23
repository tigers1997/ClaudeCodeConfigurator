"""Identity and hygiene checks for Fabric Git-integration items. Stdlib only.

A Fabric item is a folder under fabric/ that holds a `.platform` file. That file
is the item's identity: Git integration matches items across workspaces by
`config.logicalId`, so a copied folder that keeps its logicalId silently
overwrites the original on the next sync. None of that is visible to a parser
of the item's own definition files, which is why it is checked here.

Output, one line each:
  FAIL <path>: <problem>    makes the exit status 1
  WARN <path>: <problem>    advisory; never fails
  SUMMARY <text>            last line

usage: check_fabric_items.py [--root DIR]
"""

import argparse
import json
import os
import re
import subprocess
import sys

GUID = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)

# Folder suffixes Fabric Git integration treats as items. A folder named like one
# but without a .platform is ignored by Git integration: nothing syncs, no error.
ITEM_SUFFIXES = (
    ".SemanticModel",
    ".Report",
    ".Notebook",
    ".Lakehouse",
    ".Warehouse",
    ".DataPipeline",
)

SKIP_DIRS = {".git", "node_modules", ".venv"}

# Environment coordinates that should come from an environment variable,
# connection reference, deployment setting or Variable Library, never be baked
# into source. Advisory: a match may be legitimate (a public API URL), so this
# only warns.
HARDCODED = (
    (
        "Dataverse environment URL",
        re.compile(
            r"https://[A-Za-z0-9-]+\.(?:api\.)?crm[0-9]*\.dynamics\.com", re.IGNORECASE
        ),
    ),
    (
        "Power BI / Fabric workspace URL",
        re.compile(
            r"https://(?:app\.)?(?:powerbi\.com|fabric\.microsoft\.com)/groups/[0-9a-f-]{36}",
            re.IGNORECASE,
        ),
    ),
    (
        "Fabric REST URL with a workspace id",
        re.compile(
            r"api\.(?:fabric\.microsoft|powerbi)\.com/v1(?:\.0/myorg)?/(?:workspaces|groups)/[0-9a-f-]{36}",
            re.IGNORECASE,
        ),
    ),
    (
        "tenant id in a sign-in URL",
        re.compile(
            r"(?:login\.microsoftonline\.com|sts\.windows\.net)/[0-9a-f-]{36}",
            re.IGNORECASE,
        ),
    ),
    (
        "XMLA workspace connection",
        re.compile(r"powerbi://api\.powerbi\.com/v1\.0/", re.IGNORECASE),
    ),
)
MAX_SCAN_BYTES = 2 * 1024 * 1024
MAX_WARNINGS_PER_KIND = 10


def tracked_files(root):
    """Paths git tracks, or None when this is not a git repo (or git is absent)."""
    try:
        out = subprocess.run(
            ["git", "-C", root, "ls-files"],
            check=False,
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout.splitlines() if out.returncode == 0 else None


def read_json(path):
    with open(path, "rb") as fh:
        raw = fh.read()
    bom = raw.startswith(b"\xef\xbb\xbf")
    return json.loads(raw.decode("utf-8-sig")), bom


def check(root):
    fails, warns = [], []
    items = []  # (relative dir, logicalId)
    fabric = os.path.join(root, "fabric")

    def rel(p):
        return os.path.relpath(p, root).replace(os.sep, "/")

    if os.path.isdir(fabric):
        for dirpath, dirnames, filenames in os.walk(fabric):
            dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
            name = os.path.basename(dirpath)
            if ".platform" in filenames:
                items.append(check_platform(dirpath, rel, fails, warns))
            elif name.endswith(ITEM_SUFFIXES):
                fails.append(
                    f"{rel(dirpath)}: looks like a Fabric item but has no .platform file; "
                    "Git integration ignores it"
                )

    seen = {}
    for path, lid in items:
        if lid:
            seen.setdefault(lid.lower(), []).append(path)
    for lid, paths in sorted(seen.items()):
        if len(paths) > 1:
            for p in paths[1:]:
                fails.append(
                    f"{p}/.platform: shares logicalId {lid} with {paths[0]}; a copied item folder "
                    "needs a new logicalId and a new displayName, or it overwrites the original on sync"
                )

    # Power BI writes machine-local state next to the project; it is never source.
    tracked = tracked_files(root)
    local_state = re.compile(r"(^|/)\.pbi/(localSettings\.json|cache\.abf)$")
    if tracked is not None:
        for f in tracked:
            if local_state.search(f):
                fails.append(
                    f"{f}: Power BI local state is tracked by git; remove it from the index "
                    "(git rm --cached) and ignore **/.pbi/localSettings.json and **/.pbi/cache.abf"
                )
            elif f.lower().endswith(".pbix"):
                warns.append(
                    f"{f}: a .pbix is a binary that cannot be reviewed or merged; "
                    "the PBIP folder format is the source format"
                )

    scan_hardcoded(root, rel, warns)
    return items, fails, warns


def check_platform(dirpath, rel, fails, warns):
    path = rel(dirpath)
    pfile = os.path.join(dirpath, ".platform")
    try:
        data, bom = read_json(pfile)
    except (OSError, ValueError) as e:
        fails.append(f"{path}/.platform: not valid JSON ({e})")
        return path, None
    if bom:
        warns.append(
            f"{path}/.platform: starts with a UTF-8 BOM; Fabric tooling expects UTF-8 without one"
        )
    if not isinstance(data, dict):
        fails.append(f"{path}/.platform: top level must be a JSON object")
        return path, None
    if not isinstance(data.get("$schema"), str):
        fails.append(f"{path}/.platform: missing $schema")
    meta, config = data.get("metadata"), data.get("config")
    typ = meta.get("type") if isinstance(meta, dict) else None
    display = meta.get("displayName") if isinstance(meta, dict) else None
    if not (isinstance(typ, str) and typ):
        fails.append(f"{path}/.platform: metadata.type is missing")
    if not (isinstance(display, str) and display):
        fails.append(f"{path}/.platform: metadata.displayName is missing")
    lid = config.get("logicalId") if isinstance(config, dict) else None
    if not (isinstance(lid, str) and GUID.match(lid)):
        fails.append(f"{path}/.platform: config.logicalId is missing or not a GUID")
        lid = None
    if not (isinstance(config, dict) and isinstance(config.get("version"), str)):
        fails.append(f"{path}/.platform: config.version is missing")

    folder = os.path.basename(dirpath)
    if "." in folder and isinstance(typ, str) and typ:
        suffix = folder.rsplit(".", 1)[1]
        if suffix != typ:
            fails.append(
                f"{path}: the folder suffix .{suffix} does not match metadata.type '{typ}' "
                "(Git integration reads the type from .platform; was the folder renamed or copied?)"
            )
    if (
        isinstance(display, str)
        and "." in folder
        and folder.rsplit(".", 1)[0] != display
    ):
        warns.append(
            f"{path}: folder name '{folder.rsplit('.', 1)[0]}' differs from displayName '{display}' "
            "(fine if Fabric sanitised characters; otherwise a rename was half done)"
        )
    return path, lid


def scan_hardcoded(root, rel, warns):
    counts = {}
    for top in ("fabric", "power-platform"):
        base = os.path.join(root, top)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
            for fn in sorted(filenames):
                if fn.lower().endswith(
                    (
                        ".md",
                        ".msapp",
                        ".pbix",
                        ".abf",
                        ".zip",
                        ".png",
                        ".jpg",
                        ".jpeg",
                        ".gif",
                        ".ico",
                    )
                ):
                    continue
                full = os.path.join(dirpath, fn)
                try:
                    if os.path.getsize(full) > MAX_SCAN_BYTES:
                        continue
                    with open(full, "rb") as fh:
                        text = fh.read().decode("utf-8")
                except (OSError, UnicodeDecodeError):
                    continue
                for lineno, line in enumerate(text.splitlines(), 1):
                    for kind, rx in HARDCODED:
                        if (
                            rx.search(line)
                            and counts.get(kind, 0) < MAX_WARNINGS_PER_KIND
                        ):
                            counts[kind] = counts.get(kind, 0) + 1
                            warns.append(
                                f"{rel(full)}:{lineno}: {kind}; environment-specific values belong in an "
                                "environment variable, connection reference, deployment setting or Variable Library"
                            )


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--root", default=".", help="repository root (default: .)")
    root = os.path.abspath(ap.parse_args().root)
    items, fails, warns = check(root)
    for line in fails:
        print("FAIL " + line)
    for line in warns:
        print("WARN " + line)
    print(
        f"SUMMARY {len(items)} Fabric item(s), {len(fails)} problem(s), {len(warns)} warning(s)"
    )
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
