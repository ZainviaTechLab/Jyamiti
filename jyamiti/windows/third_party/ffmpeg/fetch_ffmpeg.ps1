# Downloads the static Windows ffmpeg build this project bundles for Math
# Pad's board+voice recording feature (see MathPadRecordingService).
# ffmpeg.exe itself isn't committed to git (~80MB binary, GPLv3 -- see
# NOTICE.txt) -- run this once after cloning, before building for Windows.

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$zipPath = Join-Path $scriptDir "ffmpeg-release.zip"
$exePath = Join-Path $scriptDir "ffmpeg.exe"

if (Test-Path $exePath) {
    Write-Host "ffmpeg.exe already present at $exePath -- nothing to do."
    exit 0
}

Write-Host "Downloading ffmpeg (gyan.dev essentials build)..."
Invoke-WebRequest -Uri "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" -OutFile $zipPath

Write-Host "Extracting ffmpeg.exe..."
$extractDir = Join-Path $scriptDir "_extract_tmp"
Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
$found = Get-ChildItem -Path $extractDir -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
if (-not $found) {
    throw "ffmpeg.exe not found inside the downloaded archive."
}
Copy-Item $found.FullName $exePath -Force

Remove-Item $extractDir -Recurse -Force
Remove-Item $zipPath -Force

Write-Host "Done -- ffmpeg.exe is at $exePath"
