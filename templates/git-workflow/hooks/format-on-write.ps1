# PostToolUse hook (PowerShell) -- autoformats files after Claude writes or
# edits them. PowerShell sibling of format-on-write.sh; wire under
# hooks.PostToolUse with matcher "Write|Edit".
#
# Every formatter is optional: a missing tool is skipped silently, exactly as
# in the bash version. This hook never fails the turn.
$ErrorActionPreference = 'Continue'

$raw = ''
try { $raw = [Console]::In.ReadToEnd() } catch { exit 0 }
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

$file = ''
if ($payload.PSObject.Properties.Name -contains 'tool_input' -and $payload.tool_input) {
    foreach ($n in @('file_path', 'path')) {
        if ($payload.tool_input.PSObject.Properties.Name -contains $n -and $payload.tool_input.$n) {
            $file = [string]$payload.tool_input.$n
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($file)) { exit 0 }
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { exit 0 }

# Skip generated / vendored trees.
$normalized = $file.Replace('\', '/')
foreach ($skip in @('/.git/', '/node_modules/', '/.venv/', '/dist/', '/build/')) {
    if ($normalized -like "*$skip*") { exit 0 }
}

function Have($name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }

$ext = [System.IO.Path]::GetExtension($file).ToLowerInvariant()

try {
    switch -Regex ($ext) {
        '^\.(ts|tsx|js|jsx|mjs|cjs|json|md|css|html|yml|yaml)$' {
            if (Have 'prettier') { & prettier --write --log-level=warn $file 2>$null | Out-Null }
        }
        '^\.py$' {
            if (Have 'ruff') {
                & ruff format $file 2>$null | Out-Null
                & ruff check --fix --quiet $file 2>$null | Out-Null
            }
        }
        '^\.go$' {
            if (Have 'gofmt') { & gofmt -w $file 2>$null | Out-Null }
        }
        '^\.rs$' {
            if (Have 'rustfmt') { & rustfmt --edition 2021 $file 2>$null | Out-Null }
        }
    }
} catch {
    # A formatter that errors is not a reason to fail the turn.
}

exit 0
