# ─────────────────────────────────────────────────────────────────────────────
#  Build a release Android APK with secrets injected via --dart-define-from-file.
#
#  Usage:
#    ./build_apk.ps1                    # release build
#    ./build_apk.ps1 -Clean             # flutter clean first
#
#  The Google Drive service account JSON is read from
#  secrets/google-drive-sa.json (gitignored), packaged into a temporary
#  build-defines JSON file with proper JSON escaping (newlines, quotes), and
#  passed to Flutter via --dart-define-from-file. This avoids PowerShell's
#  brittle native-command argument quoting that breaks --dart-define when the
#  value contains spaces (e.g. the "BEGIN PRIVATE KEY" line in a service
#  account JSON would get parsed as a separate filename argument).
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

# Parse the SA JSON and re-serialize compact. This collapses the structural
# CRLF newlines between fields into a single line. The literal `\n`
# escape sequences inside `private_key` survive because they're 2 characters
# in the source — they only become real newlines after JSON decoding inside
# the Dart code that consumes them. Without this collapse, Flutter passes
# the multi-line value to the Dart frontend compiler via `-D...`, the OS
# command line splits on real newlines, and the next line is mistakenly
# interpreted as a Dart entry-point URI ("Scheme not starting with
# alphabetic character" / "-DGOOGLE_DRIVE_SA_JSON={value: {").
$saObj = Get-Content -Raw -Path $saPath | ConvertFrom-Json
$saInline = $saObj | ConvertTo-Json -Depth 20 -Compress

$definesObj = [PSCustomObject]@{
  GOOGLE_DRIVE_SA_JSON = $saInline
}
$definesPath = Join-Path $PSScriptRoot "secrets/build_defines.json"
$definesObj | ConvertTo-Json -Depth 20 -Compress | Set-Content -Path $definesPath -Encoding UTF8 -NoNewline

if ($Clean) {
  Write-Host "Running flutter clean..." -ForegroundColor Cyan
  flutter clean
}

Write-Host "Building release APK..." -ForegroundColor Cyan

try {
  flutter build apk --release --dart-define-from-file=$definesPath

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
}
finally {
  # Always wipe the temp defines file — it contains the SA private key.
  if (Test-Path $definesPath) {
    Remove-Item $definesPath -Force
  }
}
