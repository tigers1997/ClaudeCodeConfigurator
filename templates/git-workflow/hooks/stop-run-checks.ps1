# Stop hook (PowerShell) -- runs the typecheck / lint / test commands you
# configured during cc-configure intake, and reports results to Claude via
# hookSpecificOutput.additionalContext on the next turn. Never blocks.
# PowerShell sibling of stop-run-checks.sh; keep the two in sync.
#
# Skipping rules (silent, not reported), same as the bash version:
#   1. Empty command -- you blanked the field during intake.
#   2. First binary not on PATH at runtime.
#   3. Stack manifest absent at the project root (package.json, pyproject.toml,
#      Cargo.toml, go.mod, Gemfile, pom.xml, build.gradle) -- so the check loop
#      stays quiet during the brainstorming/planning phase.
#   4. Background work still in flight (input carries a non-empty
#      background_tasks array) -- the real stop comes later.
$ErrorActionPreference = 'Continue'

$projectDir = $env:CLAUDE_PROJECT_DIR
if ([string]::IsNullOrWhiteSpace($projectDir)) { $projectDir = (Get-Location).Path }
Set-Location -LiteralPath $projectDir

# Skipping rule 4. Console.In.Peek() returns -1 on a closed/empty stdin, so a
# direct terminal invocation doesn't hang waiting for input.
$raw = ''
try {
    if (-not [Console]::IsInputRedirected) { $raw = '' }
    else { $raw = [Console]::In.ReadToEnd() }
} catch { $raw = '' }

if (-not [string]::IsNullOrWhiteSpace($raw)) {
    try {
        $payload = $raw | ConvertFrom-Json
        if ($payload.PSObject.Properties.Name -contains 'background_tasks' -and $payload.background_tasks) {
            if (@($payload.background_tasks).Count -gt 0) { exit 0 }
        }
    } catch { }
}

# label|command  (the 3rd docker-compose field the bash hook supports is not
# ported: it shells out to `docker compose exec -T`, and the container path is
# better served by running the bash hook under Git Bash or WSL. A 3-field entry
# is treated as a plain host command here, minus the service.)
$checks = @(
    @{ label = 'typecheck'; command = '{{cmd_typecheck}}' },
    @{ label = 'lint';      command = '{{cmd_lint}}' },
    @{ label = 'test';      command = '{{cmd_test}}' }
)

# Map a check command's first binary to the manifest that signals "this stack
# has been scaffolded". Mirrors manifest_for() in the .sh version.
function Get-ManifestFor {
    param([string]$Binary)
    switch -Regex ($Binary) {
        '^(pnpm|npm|yarn|bun)$'      { return 'package.json' }
        '^(uv|poetry|pip|pip3)$'     { return 'pyproject.toml' }
        '^(cargo|rustc)$'            { return 'Cargo.toml' }
        '^go$'                       { return 'go.mod' }
        '^(bundle|gem)$'             { return 'Gemfile' }
        '^mvn$'                      { return 'pom.xml' }
        '^(gradle|\./gradlew)$'      { return 'build.gradle' }
        default                      { return '' }
    }
}

$report = ''

foreach ($check in $checks) {
    $label = $check.label
    $cmd = [string]$check.command

    # Rule 1: user opted out of this check during intake.
    if ([string]::IsNullOrWhiteSpace($cmd)) { continue }

    $first = ($cmd -split '\s+')[0]

    # Rule 2: the tool isn't installed on this machine.
    if (-not (Get-Command $first -ErrorAction SilentlyContinue)) { continue }

    # Rule 3: the stack this check belongs to isn't scaffolded here yet.
    $manifest = Get-ManifestFor $first
    if ($manifest -and -not (Test-Path -LiteralPath (Join-Path $projectDir $manifest))) { continue }

    $output = ''
    $status = 0
    try {
        # cmd.exe /c keeps the configured command string intact (it may contain
        # pipes or flags) and merges stderr, matching the bash hook's 2>&1.
        $output = & cmd.exe /c "$cmd 2>&1" | Out-String
        $status = $LASTEXITCODE
    } catch {
        $output = $_.Exception.Message
        $status = 1
    }

    if ($status -eq 0) {
        $report += "[stop-check] ${label}: OK`n"
    } else {
        $tail = ($output -split "`r?`n" | Select-Object -Last 30) -join "`n"
        $report += "[stop-check] ${label}: FAIL (exit ${status})`n${tail}`n---`n"
    }
}

# Emit decision JSON so Claude sees the report on the next turn. Built with
# ConvertTo-Json so command output containing quotes or backslashes can't
# produce malformed JSON.
if (-not [string]::IsNullOrWhiteSpace($report)) {
    $obj = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName    = 'Stop'
            additionalContext = $report
        }
    }
    Write-Output ($obj | ConvertTo-Json -Compress -Depth 5)
}

exit 0
