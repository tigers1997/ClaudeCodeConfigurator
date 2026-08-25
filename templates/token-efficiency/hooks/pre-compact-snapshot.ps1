# PreCompact hook (PowerShell) -- writes a summary of the session before
# compaction, so there's a durable record of what was done after compression.
# PowerShell sibling of pre-compact-snapshot.sh.
#
# Never fails the turn: any unexpected condition still emits the minimal JSON
# and exits 0. A snapshot is a convenience, not a gate.
$ErrorActionPreference = 'Continue'

$raw = ''
try { $raw = [Console]::In.ReadToEnd() } catch { $raw = '' }

$sessionId = ''
if (-not [string]::IsNullOrWhiteSpace($raw)) {
    try {
        $payload = $raw | ConvertFrom-Json
        if ($payload.PSObject.Properties.Name -contains 'session_id') {
            $sessionId = [string]$payload.session_id
        }
    } catch { }
}

$projectDir = $env:CLAUDE_PROJECT_DIR
if ([string]::IsNullOrWhiteSpace($projectDir)) { $projectDir = (Get-Location).Path }

try {
    $logDir = Join-Path $projectDir '.claude\logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $ts = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $out = Join-Path $logDir "compact-$ts.md"

    # git may be absent, or this may not be a repo: every call degrades to a note.
    function Invoke-Git {
        param([string[]]$GitArgs)
        try {
            $result = & git -C $projectDir @GitArgs 2>$null
            if ($LASTEXITCODE -ne 0) { return '(git returned no output)' }
            if (-not $result) { return '(none)' }
            return ($result -join "`n")
        } catch {
            return '(git unavailable)'
        }
    }

    $lines = @(
        "# Pre-compact snapshot $ts",
        '',
        "session_id: $sessionId",
        '',
        '## Git status',
        (Invoke-Git @('status', '--short')),
        '',
        '## Recent commits (this session window)',
        (Invoke-Git @('log', '--since=6 hours ago', '--oneline')),
        '',
        '## Files changed since HEAD',
        (Invoke-Git @('diff', '--name-status'))
    )

    # UTF8 without BOM, LF endings: this file may be read on another platform.
    $text = ($lines -join "`n") + "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($out, $text, $utf8NoBom)
} catch {
    # Snapshot failed; the turn continues regardless.
}

# Emit minimal JSON -- don't inject heavy context.
Write-Output '{"suppressOutput": true}'
exit 0
