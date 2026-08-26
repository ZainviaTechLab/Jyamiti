<#
.SYNOPSIS
  One-time Windows dev-machine setup for agora_rtc_engine's native SDK.

.DESCRIPTION
  agora_rtc_engine's Windows CMake step (its own DownloadSDK.cmake)
  downloads two native SDK zips and extracts them through Flutter's
  `.plugin_symlinks` symlink -- which Windows' bundled libarchive
  refuses to extract through ("Cannot extract through symlink ..."),
  a documented hardening behavior in libarchive itself, not a bug in
  this project or in the package. `flutter build windows` /
  `flutter run -d windows` will fail with that exact CMake error until
  this is worked around.

  This script does the workaround:
    1. Relaxes Windows' symlink evaluation policy (requires an elevated
       PowerShell) -- a real prerequisite for Flutter's OWN plugin
       symlinks to resolve correctly in general on this machine, not
       just for this specific issue.
    2. Reads the exact SDK download URLs straight out of the currently
       installed agora_rtc_engine package's own DownloadSDK.cmake, so
       this script stays correct automatically if `flutter pub get`
       later picks a different agora_rtc_engine version (and therefore
       a different bundled SDK version) -- nothing here is hardcoded
       to today's specific SDK build.
    3. Downloads + extracts both SDK zips directly into the package's
       REAL (non-symlinked) pub cache location using .NET's
       Expand-Archive, which isn't subject to libarchive's restriction.
    4. Drops a `.plugin_dev` marker file -- an escape hatch the
       package itself provides (see DownloadSDK.cmake: "if the plugin
       is not in development mode") -- so its own download/extract
       step is skipped entirely on every future build, instead of
       re-attempting (and re-failing) each time.

  Safe to re-run: every step checks whether its own work is already
  done and skips it if so.

.NOTES
  Run this ONCE per machine, after `flutter pub get` and before
  `flutter build windows` / `flutter run -d windows` -- and again
  any time `flutter pub get` picks a new agora_rtc_engine version
  (delete the printed `.plugin_dev` marker path first, or just let
  step 3 re-download into the new version's package directory, which
  it will do automatically since the path is resolved fresh each run).

  Step 1 needs Administrator rights to actually take effect. Running
  this from a normal (non-elevated) PowerShell still completes steps
  2-4, but `flutter build windows` will keep failing until step 1 is
  also done from an elevated PowerShell.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

# ── Step 1: Relax Windows symlink evaluation ────────────────────────────
Write-Step "Checking whether this PowerShell is running as Administrator..."
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Warning "Not running as Administrator -- skipping the symlink policy fix (step 1)."
    Write-Warning "Right-click PowerShell > 'Run as administrator' and re-run this script, or 'flutter build windows' will keep failing with a 'Cannot extract through symlink' CMake error even after steps 2-4 below complete."
} else {
    fsutil behavior set SymlinkEvaluation L2L:1 R2R:1 L2R:1 R2L:1 | Out-Null
    Write-Host "Symlink evaluation enabled." -ForegroundColor Green
}

# ── Step 2: Locate the installed agora_rtc_engine package ──────────────
Write-Step "Locating agora_rtc_engine in the pub cache..."
$pubCacheRoot = $env:PUB_CACHE
if (-not $pubCacheRoot) {
    $pubCacheRoot = Join-Path $env:LOCALAPPDATA "Pub\Cache"
}
$hostedDir = Join-Path $pubCacheRoot "hosted\pub.dev"
$agoraDir = Get-ChildItem -Path $hostedDir -Directory -Filter "agora_rtc_engine-*" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1

if (-not $agoraDir) {
    Write-Error "agora_rtc_engine not found under $hostedDir -- run 'flutter pub get' in the jyamiti/ directory first, then re-run this script."
    exit 1
}
$windowsDir = Join-Path $agoraDir.FullName "windows"
$cmakeFile = Join-Path $windowsDir "cmake\DownloadSDK.cmake"
Write-Host "Found: $($agoraDir.Name)" -ForegroundColor Green

# ── Step 3: Skip entirely if already set up for this exact version ─────
$marker = Join-Path $windowsDir ".plugin_dev"
if (Test-Path $marker) {
    Write-Host "Already set up for $($agoraDir.Name) (.plugin_dev marker present) -- nothing to do." -ForegroundColor Green
    if (-not $isAdmin) {
        Write-Warning "Re-run this script as Administrator if you haven't already done step 1 on this machine."
    }
    exit 0
}

# ── Step 4: Read the exact SDK URLs from the package's own CMake script ─
Write-Step "Reading SDK download URLs from DownloadSDK.cmake..."
if (-not (Test-Path $cmakeFile)) {
    Write-Error "DownloadSDK.cmake not found at $cmakeFile -- agora_rtc_engine's Windows folder layout may have changed. Check that file directly."
    exit 1
}
$cmakeContent = Get-Content $cmakeFile -Raw
$irisUrl = [regex]::Match($cmakeContent, 'IRIS_SDK_DOWNLOAD_URL\s+"([^"]+)"').Groups[1].Value
$nativeUrl = [regex]::Match($cmakeContent, 'NATIVE_SDK_DOWNLOAD_URL\s+"([^"]+)"').Groups[1].Value
if (-not $irisUrl -or -not $nativeUrl) {
    Write-Error "Could not find the SDK download URLs in $cmakeFile -- the package's CMake script format may have changed. Open that file and adjust this script's regex."
    exit 1
}
Write-Host "Iris SDK:   $irisUrl"
Write-Host "Native SDK: $nativeUrl"

# ── Step 5: Download + extract both SDKs directly (bypassing libarchive) ─
function Get-AndExtractSdk {
    param([string]$Url, [string]$SubDir)

    $destDir = Join-Path $windowsDir "third_party\$SubDir"
    $libDir = Join-Path $destDir "lib"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    $zipName = [System.IO.Path]::GetFileName($Url)
    $zipPath = Join-Path $destDir $zipName

    if (-not (Test-Path $zipPath)) {
        Write-Step "Downloading $SubDir SDK ($zipName)..."
        Invoke-WebRequest -Uri $Url -OutFile $zipPath
    } else {
        Write-Host "$SubDir SDK zip already downloaded." -ForegroundColor Green
    }

    if ((Test-Path $libDir) -and (Get-ChildItem $libDir -Recurse -File -ErrorAction SilentlyContinue)) {
        Write-Host "$SubDir SDK already extracted." -ForegroundColor Green
        return
    }

    Write-Step "Extracting $SubDir SDK (via Expand-Archive, not libarchive)..."
    Expand-Archive -Path $zipPath -DestinationPath $libDir -Force
}

Get-AndExtractSdk -Url $irisUrl -SubDir "iris"
Get-AndExtractSdk -Url $nativeUrl -SubDir "native"

# ── Step 6: Drop the .plugin_dev marker ──────────────────────────────────
Write-Step "Marking agora_rtc_engine as pre-set-up (.plugin_dev)..."
New-Item -ItemType File -Path $marker -Force | Out-Null

Write-Host ""
Write-Host "Done. You can now run 'flutter build windows' or 'flutter run -d windows'." -ForegroundColor Green
if (-not $isAdmin) {
    Write-Host ""
    Write-Warning "Reminder: step 1 (symlink policy) was skipped because this wasn't run as Administrator. If the build still fails with a 'Cannot extract through symlink' error, re-run this script from an elevated PowerShell."
}
