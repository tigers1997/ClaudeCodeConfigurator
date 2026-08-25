# PreToolUse hook (PowerShell) -- blocks obviously dangerous shell commands.
# PowerShell sibling of block-dangerous-bash.sh, for Windows machines with no
# Git Bash. Scaffolded when cc-configure runs with --hook-shell powershell,
# which also sets "shell": "powershell" on the hook entry.
#
# Input (stdin): JSON with tool_input.command, plus session_id, cwd, etc.
# Output: exit 0 to allow; exit 2 to block (stderr is shown to Claude).
#
# Keep the pattern list in sync with the .sh version -- same footguns, .NET
# regex syntax ([[:space:]] -> \s). Matching is case-insensitive here because
# Windows shells are, which makes this slightly stricter than the bash hook.
$ErrorActionPreference = 'Stop'

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

try {
    $payload = $raw | ConvertFrom-Json
} catch {
    # Unparseable payload is not the user's fault and not our call to block on.
    exit 0
}

$cmd = ''
if ($payload.PSObject.Properties.Name -contains 'tool_input' -and $payload.tool_input) {
    if ($payload.tool_input.PSObject.Properties.Name -contains 'command') {
        $cmd = [string]$payload.tool_input.command
    }
}
if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

# Deny list -- extend as you find footguns. Mirrors the bash hook, plus the
# PowerShell-native spellings of the same destructive intents.
$patterns = @(
    'rm\s+-rf?\s+/+($|\s)',                       # rm -rf / (also //)
    'rm\s+-rf?\s+~/?($|\s)',                      # rm -rf ~ (also ~/)
    'rm\s+-rf?\s+"?\$HOME"?/?($|\s)',             # rm -rf $HOME / "$HOME"
    'rm\s+-rf?\s+\.($|\s)',                       # rm -rf .
    'rm\s+-rf?\s+\*',                             # rm -rf *
    ':\(\)\{.*\|:&\};:',                          # fork bomb
    '\bmkfs\b',                                   # format filesystem
    '\bdd\s+.*of=/dev/',                          # dd to device
    '>\s*/dev/sda',                               # overwrite disk
    '\bsudo\s',                                   # sudo
    'curl[^|]+\|\s*(sh|bash|zsh|pwsh|powershell)\b',   # curl | sh
    'wget[^|]+\|\s*(sh|bash|zsh|pwsh|powershell)\b',   # wget | sh
    '\bchmod\s+-R\s+777\b',                       # chmod -R 777
    '\bgit\s+push\s+.*--force\b',                 # force push
    '\bgit\s+reset\s+--hard\b',                   # hard reset
    # --- PowerShell / Windows equivalents of the same intents ---
    'Remove-Item\s+.*-Recurse.*-Force.*\s+[A-Za-z]:\\?($|\s)',   # rmdir a whole drive
    'Remove-Item\s+.*(\$HOME|\$env:USERPROFILE)',                 # wipe the profile
    '\bformat\s+[A-Za-z]:',                                       # format C:
    '\b(Invoke-WebRequest|Invoke-RestMethod|iwr|irm|curl\.exe)\b[^|]*\|\s*(iex|Invoke-Expression)',  # download | iex
    '\bicacls\b.*\/grant\s+\S+:\(?F\)?.*\/T'                      # recursive full-control grant
)

foreach ($pat in $patterns) {
    if ([System.Text.RegularExpressions.Regex]::IsMatch(
            $cmd, $pat,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        [Console]::Error.WriteLine("[block-dangerous-bash] Blocked pattern: $pat")
        [Console]::Error.WriteLine("[block-dangerous-bash] Command: $cmd")
        exit 2
    }
}

exit 0
