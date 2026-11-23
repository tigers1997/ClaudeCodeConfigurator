#!/usr/bin/env bash
# scripts/check_fabric_items.py, rule by rule, on temporary trees. It guards
# what no parser of an item's own files can see: the item's identity. A copied
# folder that keeps its logicalId silently overwrites the original on the next
# Fabric sync, which is the failure this check exists for.
set -euo pipefail

python3 - <<'EOF'
import json, os, subprocess, sys, tempfile
sys.dont_write_bytecode = True   # do not leave a __pycache__ in templates/
sys.path.insert(0, "templates/stack-microsoft-data/scripts")
import check_fabric_items as c

G1 = "11111111-1111-4111-8111-111111111111"
G2 = "22222222-2222-4222-8222-222222222222"


def platform(typ="SemanticModel", name="Sales", lid=G1, **over):
    d = {"$schema": "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json",
         "metadata": {"type": typ, "displayName": name}, "config": {"version": "2.0", "logicalId": lid}}
    d.update(over)
    return d


def tree(files):
    root = tempfile.mkdtemp()
    for path, content in files.items():
        full = os.path.join(root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as fh:
            fh.write(content if isinstance(content, bytes) else (content if isinstance(content, str) else json.dumps(content)).encode())
    return root


def run(files):
    root = tree(files)
    items, fails, warns = c.check(root)
    return items, fails, warns


def has(lines, text):
    return any(text in l for l in lines)


# clean
items, f, w = run({"fabric/Sales.SemanticModel/.platform": platform(), "fabric/Sales.Report/.platform": platform("Report", "Sales", G2)})
assert len(items) == 2 and f == [] and w == [], (f, w)

# no fabric/ at all is fine (a repo that is only Power Platform)
items, f, w = run({"power-platform/README.md": "x"})
assert items == [] and f == [], f

# not JSON, not an object, missing pieces
_, f, _ = run({"fabric/A.Notebook/.platform": "{ nope"})
assert has(f, "not valid JSON"), f
_, f, _ = run({"fabric/A.Notebook/.platform": "[]"})
assert has(f, "top level must be a JSON object"), f
_, f, _ = run({"fabric/A.Notebook/.platform": {"metadata": {}, "config": {}}})
for need in ("missing $schema", "metadata.type is missing", "metadata.displayName is missing", "config.logicalId is missing or not a GUID", "config.version is missing"):
    assert has(f, need), (need, f)
_, f, _ = run({"fabric/A.Notebook/.platform": platform("Notebook", "A", "not-a-guid")})
assert has(f, "not a GUID"), f

# the folder suffix must match metadata.type
_, f, _ = run({"fabric/Sales.Report/.platform": platform("SemanticModel", "Sales")})
assert has(f, "folder suffix .Report does not match metadata.type 'SemanticModel'"), f

# a copied item folder shares the original's logicalId: the check this file exists for
_, f, _ = run({"fabric/Sales.SemanticModel/.platform": platform(), "fabric/Sales2.SemanticModel/.platform": platform(name="Sales2")})
assert has(f, "shares logicalId") and has(f, "new logicalId and a new displayName"), f
assert sum("shares logicalId" in l for l in f) == 1, f        # one report per extra copy, not per pair
# case-insensitive GUIDs are the same id
_, f, _ = run({"fabric/A.Notebook/.platform": platform("Notebook", "A", G1.upper()), "fabric/B.Notebook/.platform": platform("Notebook", "B", G1)})
assert has(f, "shares logicalId"), f
# three copies: two extras reported
_, f, _ = run({f"fabric/N{i}.Notebook/.platform": platform("Notebook", f"N{i}") for i in range(3)})
assert sum("shares logicalId" in l for l in f) == 2, f

# a folder that looks like an item but has no .platform is ignored by Git integration
_, f, _ = run({"fabric/Ghost.SemanticModel/definition/model.tmdl": "model Model"})
assert has(f, "Ghost.SemanticModel") and has(f, "has no .platform"), f
_, f, _ = run({"fabric/notes/readme.md": "x", "fabric/Sales.SemanticModel/.platform": platform()})
assert f == [], f                                              # a plain folder is not an item
# items may sit in subfolders
items, f, _ = run({"fabric/dev/team/Sales.SemanticModel/.platform": platform()})
assert len(items) == 1 and f == [], f

# warnings, never failures
_, f, w = run({"fabric/Sales.SemanticModel/.platform": platform(name="Revenue")})
assert f == [] and has(w, "differs from displayName 'Revenue'"), (f, w)
_, f, w = run({"fabric/Sales.SemanticModel/.platform": b"\xef\xbb\xbf" + json.dumps(platform()).encode()})
assert f == [] and has(w, "UTF-8 BOM"), (f, w)

# hardcoded environment coordinates: advisory only, markdown excluded, capped
env = {
    "Dataverse environment URL": "https://contoso.crm4.dynamics.com/api/data",
    "Power BI / Fabric workspace URL": "https://app.fabric.microsoft.com/groups/" + G1,
    "Fabric REST URL with a workspace id": "https://api.fabric.microsoft.com/v1/workspaces/" + G1 + "/items",
    "tenant id in a sign-in URL": "https://login.microsoftonline.com/" + G2 + "/oauth2",
    "XMLA workspace connection": "powerbi://api.powerbi.com/v1.0/myorg/Sales",
}
for kind, line in env.items():
    _, f, w = run({"fabric/Sales.SemanticModel/.platform": platform(), "power-platform/x/Other/Customizations.xml": f"<a>{line}</a>\n"})
    assert f == [] and has(w, kind), (kind, f, w)
    _, _, w = run({"fabric/Sales.SemanticModel/.platform": platform(), "power-platform/notes.md": line})
    assert not has(w, kind), f"markdown must not be scanned: {kind}"
_, _, w = run({"fabric/Sales.SemanticModel/.platform": platform(), "power-platform/ok.xml": "https://example.com/api https://learn.microsoft.com/x\n"})
assert w == [], w
_, _, w = run({"fabric/Sales.SemanticModel/.platform": platform(), "power-platform/big.xml": "https://contoso.crm.dynamics.com\n" * 50})
assert sum("Dataverse environment URL" in l for l in w) == c.MAX_WARNINGS_PER_KIND, len(w)

# git: tracked Power BI local state fails; a tracked .pbix warns; untracked or ignored files do not
root = tree({"fabric/Sales.SemanticModel/.platform": platform(), "fabric/Sales.SemanticModel/.pbi/cache.abf": "x",
             "fabric/Sales.SemanticModel/.pbi/localSettings.json": "{}", "fabric/Old.pbix": "binary"})
g = lambda *a: subprocess.run(["git", "-C", root, "-c", "user.name=t", "-c", "user.email=t@e", "-c", "commit.gpgsign=false", *a], check=True, capture_output=True)
g("init", "-q", "-b", "main")
_, f, w = c.check(root)[0:3]
assert not has(f, ".pbi") and not has(w, ".pbix"), "files git does not track must not be reported"
g("add", "-A", "-f"); g("commit", "-q", "-m", "x")
_, f, w = c.check(root)[0:3]
assert has(f, "cache.abf: Power BI local state is tracked") and has(f, "localSettings.json: Power BI local state is tracked"), f
assert has(w, "Old.pbix: a .pbix is a binary"), w
assert has(f, "git rm --cached"), f

# CLI contract: lines, summary, exit status
root = tree({"fabric/A.Notebook/.platform": platform("Notebook", "A"), "fabric/B.Notebook/.platform": platform("Notebook", "B")})
r = subprocess.run([sys.executable, "templates/stack-microsoft-data/scripts/check_fabric_items.py", "--root", root], capture_output=True, text=True)
assert r.returncode == 1, r.stdout
lines = r.stdout.splitlines()
assert lines[-1].startswith("SUMMARY 2 Fabric item(s), 1 problem(s)"), lines[-1]
assert any(l.startswith("FAIL fabric/B.Notebook/.platform: shares logicalId") for l in lines), lines
ok = tree({"fabric/A.Notebook/.platform": platform("Notebook", "A")})
r = subprocess.run([sys.executable, "templates/stack-microsoft-data/scripts/check_fabric_items.py", "--root", ok], capture_output=True, text=True)
assert r.returncode == 0 and r.stdout.splitlines()[-1].startswith("SUMMARY 1 Fabric item(s), 0 problem(s), 0 warning(s)"), r.stdout
print("PASS: identity checker catches bad, copied and misnamed items, warns on the rest, and honours git")
EOF
