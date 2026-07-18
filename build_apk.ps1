# ─────────────────────────────────────────────────────────────────────────────
#  Build a release Android APK.
#
#  Usage:
#    ./build_apk.ps1                    # release build
#    ./build_apk.ps1 -Clean             # flutter clean first
#
#  NOTE (security): the Google Drive service-account key is NO LONGER embedded
#  in the APK. The app now fetches a short-lived Drive access token from the
#  backend's auth-gated `/api/v1/cloud/token` broker at runtime. The private key
#  lives ONLY on the server, in the backend env var `GOOGLE_DRIVE_SA_JSON`
#  (and optionally `GOOGLE_DRIVE_FOLDER_ID`). There is nothing secret to inject
#  here anymore.
# ─────────────────────────────────────────────────────────────────────────────

param(
  [switch]$Clean
)

$ErrorActionPreference = "Stop"

if ($Clean) {
  Write-Host "Running flutter clean..." -ForegroundColor Cyan
  flutter clean
}

Write-Host "Building release APK..." -ForegroundColor Cyan

flutter build apk --release

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
