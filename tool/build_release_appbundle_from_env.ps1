# Release Android App Bundle (.aab) with OpenAI-related dart-defines from flutter-app/.env
# From flutter-app:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tool\build_release_appbundle_from_env.ps1

$ErrorActionPreference = 'Stop'
$flutterAppRoot = Split-Path $PSScriptRoot -Parent
Set-Location $flutterAppRoot

$envFile = Join-Path $flutterAppRoot '.env'
if (-not (Test-Path -LiteralPath $envFile)) {
    Write-Error "Missing .env at $envFile"
}

function Get-DotEnvValueFromText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )
    $pattern = "^\s*$([regex]::Escape($Key))\s*=\s*(.*)$"
    foreach ($line in ($Text -split "`r`n|`r|`n")) {
        $t = $line.Trim()
        if ($t -match '^\s*#' -or $t -eq '') { continue }
        if ($t -match $pattern) {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

$envText = [System.IO.File]::ReadAllText($envFile, [System.Text.UTF8Encoding]::new($false))
$openAiKey = Get-DotEnvValueFromText -Text $envText -Key 'OPENAI_API_KEY'

if ([string]::IsNullOrEmpty($openAiKey)) {
    Write-Error @"
OPENAI_API_KEY not found in .env.
Add OPENAI_API_KEY=... to flutter-app/.env
"@
}

Write-Host 'Building release appbundle (dart-define from .env)...'
$flutterArgs = @(
    'build', 'appbundle', '--release',
    "--dart-define=OPENAI_API_KEY=$openAiKey"
)

$translationModel = Get-DotEnvValueFromText -Text $envText -Key 'OPENAI_TRANSLATION_MODEL'
if (-not [string]::IsNullOrEmpty($translationModel)) {
    $flutterArgs += "--dart-define=OPENAI_TRANSLATION_MODEL=$translationModel"
}

$translationTimeout = Get-DotEnvValueFromText -Text $envText -Key 'OPENAI_TRANSLATION_TIMEOUT_SECONDS'
if (-not [string]::IsNullOrEmpty($translationTimeout)) {
    $flutterArgs += "--dart-define=OPENAI_TRANSLATION_TIMEOUT_SECONDS=$translationTimeout"
}

$maxInputChars = Get-DotEnvValueFromText -Text $envText -Key 'MAIL_TRANSLATION_MAX_INPUT_CHARS'
if (-not [string]::IsNullOrEmpty($maxInputChars)) {
    $flutterArgs += "--dart-define=MAIL_TRANSLATION_MAX_INPUT_CHARS=$maxInputChars"
}

& flutter @flutterArgs

$bundle = Join-Path $flutterAppRoot 'build\app\outputs\bundle\release\app-release.aab'
if (-not (Test-Path -LiteralPath $bundle)) {
    Write-Error "AAB not found at $bundle"
}

Write-Host "OK: $bundle"
