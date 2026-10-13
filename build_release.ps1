#!/usr/bin/env pwsh
# build_release.ps1
# Builds a production release of Pomodoro Timer for Windows.
# Outputs:
#   - d:\Projects\EAII\pomodoro-phoenix\PomodoroTimer\       (full distribution)
#   - d:\Projects\EAII\pomodoro-phoenix\PomodoroTimer.exe   (root launcher with icon)

$ErrorActionPreference = "Stop"

$scriptDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$appName       = "pomodoro_app"
$launcherName  = "PomodoroTimer"
$relProdDir    = "_build\prod\rel\$appName"
$workspaceRoot = Split-Path -Parent $scriptDir
$destRelease   = Join-Path $workspaceRoot "PomodoroTimer"
$rootLauncher  = Join-Path $workspaceRoot "$launcherName.exe"
$iconPath      = Join-Path $scriptDir "priv\static\images\pomodoro.ico"
$pngPath       = Join-Path $scriptDir "priv\static\images\pomodoro.png"

Write-Host ""
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Pomodoro Timer — Windows Production Release Builder" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Workspace Root: $workspaceRoot" -ForegroundColor DarkGray
Write-Host "  App Directory:  $scriptDir" -ForegroundColor DarkGray
Write-Host "  Dest Release:   $destRelease" -ForegroundColor DarkGray
Write-Host ""

# ── Step 1: Build production assets ──────────────────────────────────────────
Write-Host '[1/6] Building production assets...' -ForegroundColor Yellow
$env:MIX_ENV = "prod"

& mix compile --force
if ($LASTEXITCODE -ne 0) { throw "mix compile failed" }

& mix assets.deploy
if ($LASTEXITCODE -ne 0) { throw "mix assets.deploy failed" }

# ── Step 2: Assemble Elixir Release ──────────────────────────────────────────
Write-Host ""
Write-Host "[2/6] Assembling Elixir production release..." -ForegroundColor Yellow
if (Test-Path $relProdDir) {
    Remove-Item -Recurse -Force $relProdDir
}
& mix release --overwrite
if ($LASTEXITCODE -ne 0) { throw "mix release failed" }

# ── Step 3: Run Database Migrations & Seeds ───────────────────────────────────
Write-Host ""
Write-Host "[3/6] Running release database migrations & seeds..." -ForegroundColor Yellow
$relBat = Join-Path $relProdDir "bin\$appName.bat"
if (Test-Path $relBat) {
    & $relBat eval "PomodoroApp.Release.migrate()"
    & $relBat eval "PomodoroApp.Release.seed()"
    Write-Host "    Migrations and 8-week seeds initialized successfully." -ForegroundColor Green
}

# ── Step 4: Deploy Release to pomodoro-phoenix Root ─────────────────────────
Write-Host ""
Write-Host "[4/6] Deploying release package to pomodoro-phoenix root..." -ForegroundColor Yellow

if (Test-Path $destRelease) {
    Write-Host "    Cleaning existing $destRelease..." -ForegroundColor DarkGray
    Remove-Item -Recurse -Force $destRelease
}
New-Item -ItemType Directory -Path $destRelease -Force | Out-Null

Write-Host "    Copying release binaries and runtime..." -ForegroundColor DarkGray
Copy-Item -Path "$relProdDir\*" -Destination $destRelease -Recurse -Force

# Copy music_pomodoro into release so standalone player has all tracks
$musicSource = Join-Path $scriptDir "music_pomodoro"
if (Test-Path $musicSource) {
    Write-Host "    Copying Brain.fm audio library into release..." -ForegroundColor DarkGray
    Copy-Item -Path $musicSource -Destination (Join-Path $destRelease "music_pomodoro") -Recurse -Force
}

# Copy app icons into release
if (Test-Path $iconPath) {
    Copy-Item -Path $iconPath -Destination (Join-Path $destRelease "pomodoro.ico") -Force
    Copy-Item -Path $iconPath -Destination (Join-Path $destRelease "bin\pomodoro.ico") -Force
}
if (Test-Path $pngPath) {
    Copy-Item -Path $pngPath -Destination (Join-Path $destRelease "pomodoro.png") -Force
    Copy-Item -Path $pngPath -Destination (Join-Path $destRelease "bin\pomodoro.png") -Force
}

# ── Step 5: Compile Native C# Launcher with Embedded Icon ────────────────────
Write-Host ""
Write-Host "[5/6] Compiling native launcher with embedded 3D timer icon..." -ForegroundColor Yellow

$csharpSource = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

class Launcher {
    [STAThread]
    static void Main(string[] args) {
        string exePath    = Assembly.GetExecutingAssembly().Location;
        string currentDir = Path.GetDirectoryName(exePath);

        string pathFromRoot = Path.Combine(currentDir, "PomodoroTimer", "bin", "$appName.bat");
        string pathFromDir  = Path.Combine(currentDir, "bin", "$appName.bat");
        string pathFromBin  = Path.Combine(currentDir, "$appName.bat");

        string bat = null;
        string workDir = null;

        if (File.Exists(pathFromRoot)) {
            bat = pathFromRoot;
            workDir = Path.Combine(currentDir, "PomodoroTimer");
        } else if (File.Exists(pathFromDir)) {
            bat = pathFromDir;
            workDir = currentDir;
        } else if (File.Exists(pathFromBin)) {
            bat = pathFromBin;
            workDir = Path.GetDirectoryName(currentDir);
        }

        if (bat == null || !File.Exists(bat)) {
            MessageBox.Show(
                "Could not find $appName.bat.\n\nSearched locations:\n" +
                "- " + pathFromRoot + "\n- " + pathFromDir + "\n- " + pathFromBin,
                "Pomodoro Timer — Launch Error",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
            return;
        }

        var psi = new ProcessStartInfo {
            FileName         = "cmd.exe",
            Arguments        = "/c \"" + bat + "\" start",
            WindowStyle      = ProcessWindowStyle.Hidden,
            CreateNoWindow   = true,
            UseShellExecute  = false,
            WorkingDirectory = workDir
        };

        try {
            Process.Start(psi);
        } catch (Exception ex) {
            MessageBox.Show(
                "Error launching Pomodoro Timer: " + ex.Message,
                "Pomodoro Timer — Launch Error",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
        }
    }
}
"@

$tempCs = Join-Path $env:TEMP "PomodoroLauncher.cs"
Set-Content -Path $tempCs -Value $csharpSource -Encoding UTF8

$cscPaths = @(
    "${env:WINDIR}\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "${env:WINDIR}\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$csc = $cscPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($csc) {
    Write-Host "    Found .NET C# compiler: $csc" -ForegroundColor DarkGray
    $iconAbs = (Resolve-Path $iconPath).Path

    # 1. Compile root launcher: d:\Projects\EAII\pomodoro-phoenix\PomodoroTimer.exe
    & $csc /nologo /optimize+ /target:winexe /win32icon:"$iconAbs" /out:"$rootLauncher" /r:System.Windows.Forms.dll "$tempCs"
    if ($LASTEXITCODE -ne 0) { throw "Root launcher compilation failed" }
    Write-Host "    Compiled: $rootLauncher" -ForegroundColor Green

    # 2. Compile distribution launcher inside PomodoroTimer\PomodoroTimer.exe
    $destLauncher = Join-Path $destRelease "$launcherName.exe"
    & $csc /nologo /optimize+ /target:winexe /win32icon:"$iconAbs" /out:"$destLauncher" /r:System.Windows.Forms.dll "$tempCs"
    if ($LASTEXITCODE -ne 0) { throw "Dist launcher compilation failed" }
    Write-Host "    Compiled: $destLauncher" -ForegroundColor Green

    # 3. Compile launcher inside PomodoroTimer\bin\PomodoroTimer.exe
    $destBinLauncher = Join-Path $destRelease "bin\$launcherName.exe"
    & $csc /nologo /optimize+ /target:winexe /win32icon:"$iconAbs" /out:"$destBinLauncher" /r:System.Windows.Forms.dll "$tempCs"
    if ($LASTEXITCODE -ne 0) { throw "Bin launcher compilation failed" }
    Write-Host "    Compiled: $destBinLauncher" -ForegroundColor Green
} else {
    throw "csc.exe (.NET Framework compiler) was not found on this system."
}

# ── Step 6: Summary ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  BUILD COMPLETE!" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Root Launcher    : $rootLauncher" -ForegroundColor White
Write-Host "  Release Package  : $destRelease" -ForegroundColor White
Write-Host "  App & Tray Icon  : Embedded multi-resolution 3D timer icon" -ForegroundColor White
Write-Host ""
Write-Host "  To run: Double-click PomodoroTimer.exe in the root of pomodoro-phoenix." -ForegroundColor Cyan
Write-Host ""
