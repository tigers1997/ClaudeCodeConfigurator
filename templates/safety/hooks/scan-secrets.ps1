# PreToolUse hook (PowerShell) -- blocks Write/Edit that would land a secret in
# a file. PowerShell sibling of scan-secrets.sh; wire under hooks.PreToolUse
# with matcher "Write|Edit".
#
# Exit 0 allows, exit 2 blocks (stderr is shown to Claude).
$ErrorActionPreference = 'Stop'

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

$toolInput = $null
if ($payload.PSObject.Properties.Name -contains 'tool_input') { $toolInput = $payload.tool_input }
if (-not $toolInput) { exit 0 }

function Get-Field {
    param($Obj, [string[]]$Names)
    foreach ($n in $Names) {
        if ($Obj.PSObject.Properties.Name -contains $n -and $Obj.$n) { return [string]$Obj.$n }
    }
    return ''
}

$pathField = Get-Field $toolInput @('file_path', 'path', 'notebook_path')
$content = Get-Field $toolInput @('content', 'new_string')

# Block writes to sensitive files outright. Matched on the normalized path so a
# Windows backslash path is judged the same as a POSIX one.
$normalized = $pathField.Replace('\', '/')
$sensitive = @(
    '\.env$', '\.env\.', '/credentials', '/id_rsa$', '/id_ed25519$',
    '\.pem$', '\.key$', '\.p12$', '\.pfx$'
)
foreach ($pat in $sensitive) {
    if ([regex]::IsMatch($normalized, $pat, 'IgnoreCase')) {
        [Console]::Error.WriteLine("[scan-secrets] Refusing to write to sensitive file: $pathField")
        exit 2
    }
}

if ([string]::IsNullOrEmpty($content)) { exit 0 }

# Regex patterns for common secrets. Case-sensitive on purpose: these are
# fixed-case prefixes, and folding case here produces false positives.
$patterns = @(
    'AKIA[0-9A-Z]{16}',                                 # AWS access key
    'sk-[A-Za-z0-9]{20,}',                              # OpenAI / Anthropic-ish
    'ghp_[A-Za-z0-9]{20,}',                             # GitHub PAT
    'xox[abpr]-[A-Za-z0-9-]{10,}',                      # Slack
    '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----',  # private keys
    'glpat-[A-Za-z0-9_\-]{20,}',                        # GitLab PAT
    'eyJ[A-Za-z0-9_\-]{20,}\.eyJ[A-Za-z0-9_\-]{20,}\.'  # JWT-ish
)

foreach ($pat in $patterns) {
    if ([regex]::IsMatch($content, $pat)) {
        [Console]::Error.WriteLine("[scan-secrets] Blocked: content matches secret pattern /$pat/")
        [Console]::Error.WriteLine("[scan-secrets] File: $pathField")
        exit 2
    }
}

exit 0
