# ─────────────────────────────────────────────────────────────────────────────
#  Build a release Android APK with secrets injected via --dart-define.
#
#  Usage:
#    ./build_apk.ps1                    # release build
#    ./build_apk.ps1 -Clean             # flutter clean first
#
#  The Google Drive service account JSON is read from secrets/google-drive-sa.json
#  (gitignored) and passed to the Dart compiler via --dart-define so it never
#  lives in source code.
# ─────────────────────────────────────────────────────────────────────────────

param(
  [switch]$Clean
)

$ErrorActionPreference = "Stop"

$saPath = Join-Path $PSScriptRoot "secrets/google-drive-sa.json"
if (-not (Test-Path $saPath)) {
  Write-Host "ERROR: $saPath not found." -ForegroundColor Red
  Write-Host "Place your Google Drive service account JSON there first." -ForegroundColor Yellow
  exit 1
}

$saJson = Get-Content -Raw -Path $saPath
# Collapse to a single line so it survives the command-line.
$saJsonInline = ($saJson -replace "`r?`n", "") -replace "\s+", " "

if ($Clean) {
  Write-Host "Running flutter clean..." -ForegroundColor Cyan
  flutter clean
}

Write-Host "Building release APK..." -ForegroundColor Cyan

flutter build apk --release `
  --dart-define="GOOGLE_DRIVE_SA_JSON=$saJsonInline"

if ($LASTEXITCODE -ne 0) {
  Write-Host "Build failed." -ForegroundColor Red
  exit $LASTEXITCODE
}

$apk = "build/app/outputs/flutter-apk/app-release.apk"
if (Test-Path $apk) {
  $size = [math]::Round((Get-Item $apk).Length / 1MB, 1)
  Write-Host "Built $apk ($size MB)" -ForegroundColor Green
} else {
  Write-Host "APK not found at expected path." -ForegroundColor Red
  exit 1
}
