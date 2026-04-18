param(
    [string] $MailNotifyApiBaseUrl,
    [string] $DeviceRegistrationSecret,
    [string] $DevelopmentConfigPath = "assets/config/notification_dev.json",
    [string] $BuildName,
    [string] $BuildNumber
)

$ErrorActionPreference = "Stop"

if (Test-Path -LiteralPath $DevelopmentConfigPath) {
    $developmentConfig = Get-Content -Raw -LiteralPath $DevelopmentConfigPath |
        ConvertFrom-Json

    if ([string]::IsNullOrWhiteSpace($MailNotifyApiBaseUrl)) {
        $MailNotifyApiBaseUrl = $developmentConfig.apiBaseUrl
    }

    if ([string]::IsNullOrWhiteSpace($DeviceRegistrationSecret)) {
        $DeviceRegistrationSecret = $developmentConfig.deviceRegistrationSecret
    }
}

if ([string]::IsNullOrWhiteSpace($MailNotifyApiBaseUrl)) {
    $MailNotifyApiBaseUrl = "https://mailadmin.finestar.hr"
}

if ([string]::IsNullOrWhiteSpace($DeviceRegistrationSecret)) {
    throw "DeviceRegistrationSecret is required. Pass -DeviceRegistrationSecret or create $DevelopmentConfigPath."
}

$arguments = @(
    "build",
    "appbundle",
    "--release",
    "--dart-define=MAIL_NOTIFY_API_BASE_URL=$MailNotifyApiBaseUrl",
    "--dart-define=DEVICE_REGISTRATION_SECRET=$DeviceRegistrationSecret"
)

if (-not [string]::IsNullOrWhiteSpace($BuildName)) {
    $arguments += "--build-name=$BuildName"
}

if (-not [string]::IsNullOrWhiteSpace($BuildNumber)) {
    $arguments += "--build-number=$BuildNumber"
}

flutter @arguments
