#!/usr/bin/env bash
# scripts/report_diagnostics.py turns the PBIR validator's JSON into lines and
# an exit status. Exit 3 is the important one: output that is not the validator's
# JSON means the tool never ran (no network for npx, a crash), which validate.sh
# reports as a SKIP and not as a verdict on the report.
set -euo pipefail

python3 - <<'EOF'
import json, os, subprocess, sys

SCRIPT = "templates/stack-microsoft-data/scripts/report_diagnostics.py"


def run(text, cwd=None):
    r = subprocess.run([sys.executable, SCRIPT], input=text, capture_output=True, text=True, cwd=cwd)
    return r.returncode, r.stdout.splitlines()


def env(result, diagnostics=None, errors=0, warnings=0):
    data = {"result": result, "errorCount": errors, "warningCount": warnings, "reportPath": "/x/Sales.Report"}
    if diagnostics is not None:
        data["diagnostics"] = diagnostics
    return json.dumps({"data": data})


# succeeded, no diagnostics key at all (the real tool omits it)
rc, out = run(env("succeeded"))
assert rc == 0 and out == [], (rc, out)

# succeeded with a warning: still 0, the warning is printed
rc, out = run(env("succeeded", {"PBIR_PAGE_DIR_NOT_IN_ORDER": {"severity": "warning", "items": [{"message": "Page directory exists but not in pageOrder: \"p2\""}]}}, 0, 1))
assert rc == 0 and out == ['WARNING PBIR_PAGE_DIR_NOT_IN_ORDER: Page directory exists but not in pageOrder: "p2"'], (rc, out)

# failed: 1, one line per item, in the tool's own codes; absolute paths become repo-relative
cwd = os.getcwd()
diag = {"PBIR_VERSION_MISSING": {"severity": "error", "items": [{"message": f"Missing: {cwd}/fabric/Sales.Report/definition/version.json"}]},
        "PBIR_SCHEMA_VALIDATION_ERROR": {"severity": "error", "items": [{"message": "a"}, {"message": "b"}]}}
rc, out = run(env("failed", diag, 3, 0), cwd=cwd)
assert rc == 1, rc
assert out[0] == "ERROR PBIR_VERSION_MISSING: Missing: fabric/Sales.Report/definition/version.json", out
assert out[1:] == ["ERROR PBIR_SCHEMA_VALIDATION_ERROR: a", "ERROR PBIR_SCHEMA_VALIDATION_ERROR: b"], out

# npm and npx print notices around the JSON; the envelope is still found
noisy = "npm notice New major version\nnpm notice To update run: ...\n" + env("failed", diag, 1, 0) + "\nnpm notice\n"
rc, out = run(noisy, cwd=cwd)
assert rc == 1 and out[0].startswith("ERROR PBIR_VERSION_MISSING"), (rc, out)

# a diagnostic with no items still reports its code
rc, out = run(env("failed", {"PBIR_X": {"severity": "error", "items": []}}, 1, 0))
assert rc == 1 and out == ["ERROR PBIR_X:"], (rc, out)

# not the validator's output at all: exit 3, and the first line says why
for garbage, first in (("npm ERR! code ENOTFOUND\nnpm ERR! network\n", "npm ERR! code ENOTFOUND"),
                       ("", "(no output)"), ("\n\n", "(no output)"),
                       ('{"data": ', '{"data":'), ('{"error": "boom"}', '{"error": "boom"}'),
                       ("Segmentation fault", "Segmentation fault")):
    rc, out = run(garbage)
    assert rc == 3 and out == [first], (garbage, rc, out)
rc, out = run("x" * 500)
assert rc == 3 and len(out[0]) == 200, len(out[0])

print("PASS: PBIR diagnostics are formatted per code, noise-tolerant, repo-relative, and a non-verdict is exit 3")
EOF
