# Build debug APK and install to the first adb device (start LDPlayer first).
# Uses Firebase Auth + Cloud Functions — no LAN API URL needed.
param()

$ErrorActionPreference = "Stop"
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$root = $PSScriptRoot

Push-Location $root
try {
  .\gradlew.bat assembleDebug
  $apk = Join-Path $root "app\build\outputs\apk\debug\app-debug.apk"
  & $adb devices
  & $adb install -r $apk
  Write-Host "Installed $apk (Firebase project: adplay-sats)"
} finally {
  Pop-Location
}
