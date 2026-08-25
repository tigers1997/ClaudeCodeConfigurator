# microbit-enforcer (PowerShell): PreToolUse hook for the /freeze, /guard and
# /careful microbits. PowerShell sibling of microbit-enforcer.sh.
#
# Reads the tool-call payload from stdin (Claude Code PreToolUse contract).
# Exits 0 to allow the call; exits non-zero to block. Emits
# {"action":"ask",...} on stdout for /careful matches so Claude Code surfaces a
# confirmation prompt.
#
# Marker files (project-local, session-scoped):
#   .claude/.frozen   -- present  => block ALL Write/Edit/NotebookEdit
#   .claude/.guarded  -- newline-separated globs; block on match
#   .claude/.careful  -- newline-separated globs; prompt before match
#
# Lifecycle: a SessionStart hook (matcher startup|clear) clears all three on a
# fresh session or /clear. Markers survive --resume, compaction and /fork, so a
# long session keeps its markers.
$ErrorActionPreference = 'Stop'

$projectDir = $env:CLAUDE_PROJECT_DIR
if ([string]::IsNullOrWhiteSpace($projectDir)) { $projectDir = (Get-Location).Path }

$frozenFile  = Join-Path $projectDir '.claude\.frozen'
$guardedFile = Join-Path $projectDir '.claude\.guarded'
$carefulFile = Join-Path $projectDir '.claude\.careful'

$raw = ''
try { $raw = [Console]::In.ReadToEnd() } catch { exit 0 }
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

$toolName = ''
if ($payload.PSObject.Properties.Name -contains 'tool_name') { $toolName = [string]$payload.tool_name }

# Only Write/Edit/NotebookEdit are gated. Others pass through.
if ($toolName -notin @('Write', 'Edit', 'NotebookEdit')) { exit 0 }

$targetPath = ''
if ($payload.PSObject.Properties.Name -contains 'tool_input' -and $payload.tool_input) {
    foreach ($n in @('file_path', 'notebook_path')) {
        if ($payload.tool_input.PSObject.Properties.Name -contains $n -and $payload.tool_input.$n) {
            $targetPath = [string]$payload.tool_input.$n
            break
        }
    }
}

# 1. Frozen check -- overrides everything.
if (Test-Path -LiteralPath $frozenFile -PathType Leaf) {
    [Console]::Error.WriteLine('[ FROZEN ] Write/Edit/NotebookEdit blocked until /unfreeze.')
    exit 1
}

# Glob matching. The bash hook uses shell globs against the raw path; here the
# comparison runs on the forward-slash form of both sides so a pattern written
# as src/**/*.py still matches a Windows path the tool reported with
# backslashes. -like understands * and ?, which is the subset these markers use.
function Test-GlobMatch {
    param([string]$Path, [string]$Pattern)
    $p = $Path.Replace('\', '/')
    $g = $Pattern.Trim().Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($g)) { return $false }
    if ($p -like $g) { return $true }
    # `**/` should also match zero directories: src/**/*.py vs src/main.py
    if ($g -match '\*\*/') {
        $collapsed = $g -replace '\*\*/', ''
        if ($p -like $collapsed) { return $true }
    }
    return $false
}

function Read-Patterns {
    param([string]$File)
    try {
        return @(Get-Content -LiteralPath $File -ErrorAction Stop |
                 Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    } catch {
        return @()
    }
}

# 2. Guarded check (block on match).
if ((Test-Path -LiteralPath $guardedFile -PathType Leaf) -and $targetPath) {
    foreach ($pattern in (Read-Patterns $guardedFile)) {
        if (Test-GlobMatch $targetPath $pattern) {
            [Console]::Error.WriteLine("[ GUARDED ] $targetPath matches '$pattern' -- edit blocked.")
            exit 1
        }
    }
}

# 3. Careful check (prompt on match).
if ((Test-Path -LiteralPath $carefulFile -PathType Leaf) -and $targetPath) {
    foreach ($pattern in (Read-Patterns $carefulFile)) {
        if (Test-GlobMatch $targetPath $pattern) {
            $question = "About to write '$targetPath' (matches careful pattern '$pattern'). Proceed?"
            # Build via ConvertTo-Json so a quote or backslash in the path can't
            # produce malformed JSON, which the bash heredoc version can.
            $obj = [ordered]@{ action = 'ask'; question = $question }
            Write-Output ($obj | ConvertTo-Json -Compress)
            exit 0
        }
    }
}

# Default: allow.
exit 0
