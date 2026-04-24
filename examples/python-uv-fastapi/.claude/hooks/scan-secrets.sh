#!/usr/bin/env bash
# PreToolUse hook — blocks Write/Edit that would land a secret in a file.
# Wire under hooks.PreToolUse with matcher: "Write|Edit".
set -euo pipefail

INPUT="$(cat)"
PATH_FIELD="$(printf '%s' "$INPUT" | python3 -c 'import json,sys;d=json.load(sys.stdin).get("tool_input",{});print(d.get("file_path") or d.get("path") or "")')"
CONTENT="$(printf '%s' "$INPUT" | python3 -c 'import json,sys;d=json.load(sys.stdin).get("tool_input",{});print(d.get("content") or d.get("new_string") or "")')"

# Block writes to sensitive files outright.
case "$PATH_FIELD" in
  *.env|*.env.*|*/credentials*|*/id_rsa|*/id_ed25519|*.pem|*.key|*.p12|*.pfx)
    echo "[scan-secrets] Refusing to write to sensitive file: $PATH_FIELD" >&2
    exit 2
    ;;
esac

# Regex patterns for common secrets.
PATTERNS=(
  'AKIA[0-9A-Z]{16}'                                    # AWS access key
  'sk-[A-Za-z0-9]{20,}'                                 # OpenAI / Anthropic-ish
  'ghp_[A-Za-z0-9]{20,}'                                # GitHub PAT
  'xox[abpr]-[A-Za-z0-9-]{10,}'                         # Slack
  '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'     # private keys
  'glpat-[A-Za-z0-9_\-]{20,}'                           # GitLab PAT
  'eyJ[A-Za-z0-9_\-]{20,}\.eyJ[A-Za-z0-9_\-]{20,}\.'    # JWT-ish
)

for pat in "${PATTERNS[@]}"; do
  if printf '%s' "$CONTENT" | grep -Eq "$pat"; then
    echo "[scan-secrets] Blocked: content matches secret pattern /$pat/" >&2
    echo "[scan-secrets] File: $PATH_FIELD" >&2
    exit 2
  fi
done

exit 0
