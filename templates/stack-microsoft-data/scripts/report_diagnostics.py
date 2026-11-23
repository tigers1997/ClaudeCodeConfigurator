"""Turn `powerbi-report-author validate` JSON into one line per diagnostic.

Reads the tool's output on stdin. npm or npx may print notices before the JSON,
so the envelope is the last line that parses as one.

Prints `ERROR|WARNING CODE: message`, then exits
  0  the report validated (warnings, if any, are still printed)
  1  it did not
  3  the output was not the validator's JSON at all (the tool never ran: no
     network for npx, wrong Node, a crash). validate.sh reports that as a SKIP,
     not as a verdict on the report.
"""

import json
import os
import sys


def main() -> int:
    raw = sys.stdin.read()
    data = None
    for line in reversed(raw.splitlines()):
        if line.lstrip().startswith("{"):
            try:
                data = json.loads(line)["data"]
                break
            except (ValueError, KeyError, TypeError):
                continue
    if data is None:
        first = next(
            (ln.strip() for ln in raw.splitlines() if ln.strip()), "(no output)"
        )
        print(first[:200])
        return 3
    here = (
        os.getcwd() + os.sep
    )  # the validator prints absolute paths; show repo-relative ones
    for code, diag in (data.get("diagnostics") or {}).items():
        severity = str(diag.get("severity", "error")).upper()
        for item in diag.get("items", []) or [{}]:
            print(
                f"{severity} {code}: {item.get('message', '').replace(here, '')}".rstrip()
            )
    return 0 if data.get("result") == "succeeded" else 1


if __name__ == "__main__":
    sys.exit(main())
