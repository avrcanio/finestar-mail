# Reads OpenAI-related vars from flutter-app/.env and builds debug APK with --dart-define.
# From flutter-app:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tool\build_debug_apk_with_openai_env.ps1 -Install

param([switch]$Install)

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
Add one line to flutter-app/.env, for example:
OPENAI_API_KEY=sk-your-key-here
"@
}

Write-Host 'Building debug APK (dart-define from .env)...'
$flutterArgs = @(
    'build', 'apk', '--debug',
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

$apk = Join-Path $flutterAppRoot 'build\app\outputs\flutter-apk\app-debug.apk'
if (-not (Test-Path -LiteralPath $apk)) {
    Write-Error "APK not found at $apk"
}

if ($Install) {
    Write-Host 'Installing via adb...'
    adb install -r $apk
}
