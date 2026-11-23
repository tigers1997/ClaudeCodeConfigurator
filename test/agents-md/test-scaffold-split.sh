#!/usr/bin/env bash
# agents-md splits the project memory: AGENTS.md carries the harness-neutral
# half, CLAUDE.md becomes a bridge whose first line imports it and keeps only
# the Claude Code specifics. Neither file may leak the other's content, and
# neither may contain an unresolved {{placeholder}}.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

python3 configure.py --persona solo-experienced --yes --harness agents-md --dir "$tmp" >/dev/null
agents="$tmp/AGENTS.md"
claude="$tmp/CLAUDE.md"
[ -f "$agents" ] || { echo "FAIL: AGENTS.md not scaffolded"; exit 1; }
[ -f "$claude" ] || { echo "FAIL: CLAUDE.md not scaffolded"; exit 1; }

# The import is the ONLY thing that makes Claude Code read AGENTS.md.
first=$(head -n1 "$claude")
[ "$first" = "@AGENTS.md" ] \
    || { echo "FAIL: CLAUDE.md first line is '$first', expected '@AGENTS.md'"; exit 1; }

# AGENTS.md carries the neutral half, plus the two sections it adds.
for h in '^## WHY' '^## WHAT' '^### Commands$' '^### Code style$' '^### Testing$' \
         '^### Git workflow$' '^## Known gotchas$' '^## Agent roles$' '^## Code Review Rules$'; do
    grep -qE "$h" "$agents" || { echo "FAIL: AGENTS.md lacks '$h'"; exit 1; }
done

# Claude Code specifics must not leak into the file every other harness reads.
for leak in '.claude/' 'Working with Claude' 'Claude Code behavior rules' \
            'Token efficiency rules' 'Repo bootstrap' 'MCP servers'; do
    if grep -qF "$leak" "$agents"; then
        echo "FAIL: AGENTS.md leaks Claude Code content: '$leak'"; exit 1
    fi
done

# CLAUDE.md keeps the Claude half. The three value-add headings must survive:
# the retrofit append strategy matches them by exact text.
for h in '^## Working with Claude \(collaboration patterns\)$' '^## Claude Code behavior rules$' \
         '^## Token efficiency rules$' '^## Repo bootstrap$' '^## MCP servers$' '^## Shared instructions$'; do
    grep -qE "$h" "$claude" || { echo "FAIL: CLAUDE.md lacks '$h'"; exit 1; }
done

# ... and must not duplicate the neutral half it imports.
for h in '^## WHY' '^## WHAT' '^### Commands$' '^### Code style$' '^## Design features$'; do
    if grep -qE "$h" "$claude"; then
        echo "FAIL: CLAUDE.md duplicates AGENTS.md content: '$h'"; exit 1
    fi
done

if grep -n '{{' "$agents" "$claude"; then
    echo "FAIL: unresolved {{placeholder}} in the rendered split"; exit 1
fi

# Codex truncates its AGENTS.md chain at 32768 bytes; the scaffold budget is 20 KiB.
size=$(wc -c < "$agents" | tr -d ' ')
[ "$size" -lt 20480 ] || { echo "FAIL: AGENTS.md is $size bytes (budget 20480)"; exit 1; }

# agents-md alone must not write the Gemini adapter.
[ ! -e "$tmp/GEMINI.md" ] || { echo "FAIL: GEMINI.md written without the gemini harness"; exit 1; }

echo "PASS: agents-md splits CLAUDE.md into an AGENTS.md source of truth plus an @AGENTS.md bridge"
