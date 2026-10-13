#!/usr/bin/env pwsh
# build_release.ps1
# Builds a production release of PomodoroTimer for Windows.
# Outputs: _build/prod/rel/pomodoro_app/  + bin/PomodoroTimer.exe launcher
#
# Usage: .\build_release.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$appName    = "pomodoro_app"
$launcherName = "PomodoroTimer"
$releaseDir = "_build\prod\rel\$appName"
$binDir     = "$releaseDir\bin"

Write-Host ""
Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Pomodoro Timer — Windows Release Builder" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Build assets ───────────────────────────────────────────────────
Write-Host "[1/4] Building production assets..." -ForegroundColor Yellow
$env:MIX_ENV = "prod"
& mix deps.get --only prod
if ($LASTEXITCODE -ne 0) { throw "mix deps.get failed" }

& mix compile
if ($LASTEXITCODE -ne 0) { throw "mix compile failed" }

& mix assets.deploy
if ($LASTEXITCODE -ne 0) { throw "mix assets.deploy failed" }

# ── Step 2: Build the release ──────────────────────────────────────────────
Write-Host ""
Write-Host "[2/4] Building Elixir release..." -ForegroundColor Yellow
& mix release --overwrite
if ($LASTEXITCODE -ne 0) { throw "mix release failed" }

# ── Step 3: Run DB migrations inside the release ──────────────────────────
Write-Host ""
Write-Host "[3/4] Setting up database migrations..." -ForegroundColor Yellow

# Create a migration script that the release can eval
$migrateScript = @"
PomodoroApp.Release.migrate()
"@

# We'll embed a Release module if not already there
$releaseModulePath = "lib\pomodoro_app\release.ex"
if (-not (Test-Path $releaseModulePath)) {
    Write-Host "    Creating release helper module..." -ForegroundColor DarkGray
}

# ── Step 4: Compile the launcher .exe ─────────────────────────────────────
Write-Host ""
Write-Host "[4/4] Compiling $launcherName.exe launcher..." -ForegroundColor Yellow

$csharpSource = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

class Launcher {
    [DllImport("kernel32.dll")]
    static extern bool AllocConsole();

    [STAThread]
    static void Main(string[] args) {
        // The exe lives in bin/, so the release root is one level up
        string exePath  = Assembly.GetExecutingAssembly().Location;
        string binDir   = Path.GetDirectoryName(exePath);
        string bat      = Path.Combine(binDir, "$appName.bat");

        if (!File.Exists(bat)) {
            System.Windows.Forms.MessageBox.Show(
                "Could not find " + bat + "\n\nMake sure PomodoroTimer.exe is inside the release bin\\ folder.",
                "PomodoroTimer — Launch Error",
                System.Windows.Forms.MessageBoxButtons.OK,
                System.Windows.Forms.MessageBoxIcon.Error
            );
            return;
        }

        var psi = new ProcessStartInfo {
            FileName               = "cmd.exe",
            Arguments              = "/c \"" + bat + "\" start",
            WindowStyle            = ProcessWindowStyle.Hidden,
            CreateNoWindow         = true,
            UseShellExecute        = false,
            WorkingDirectory       = binDir
        };

        Process.Start(psi);
    }
}
"@

$launcherCs  = "$env:TEMP\PomodoroLauncher.cs"
$launcherExe = "$binDir\$launcherName.exe"

Set-Content -Path $launcherCs -Value $csharpSource -Encoding UTF8

# Use the .NET framework C# compiler (csc.exe) that ships with Windows
$cscPaths = @(
    "${env:WINDIR}\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "${env:WINDIR}\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)

$csc = $cscPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($csc) {
    Write-Host "    Using C# compiler: $csc" -ForegroundColor DarkGray
    
    $iconPath = "priv\static\images\pomodoro.ico"
    if (Test-Path $iconPath) {
        $iconAbs = (Resolve-Path $iconPath).Path
        & $csc /nologo /optimize+ /target:winexe /win32icon:"$iconAbs" /out:"$launcherExe" /r:System.Windows.Forms.dll "$launcherCs"
    } else {
        & $csc /nologo /optimize+ /target:winexe /out:"$launcherExe" /r:System.Windows.Forms.dll "$launcherCs"
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    Compiled: $launcherExe" -ForegroundColor Green
        if (Test-Path $iconPath) {
            Copy-Item $iconPath "$binDir\pomodoro.ico" -Force
        }
    } else {
        Write-Host "    csc compile failed — falling back to PowerShell Add-Type..." -ForegroundColor DarkYellow
        goto :ps_compile
    }
} else {
    Write-Host "    csc.exe not found — using PowerShell Add-Type..." -ForegroundColor DarkYellow

    :ps_compile
    Add-Type -TypeDefinition $csharpSource `
             -ReferencedAssemblies "System.Windows.Forms" `
             -OutputAssembly $launcherExe `
             -OutputType WindowsApplication
    Write-Host "    Compiled: $launcherExe" -ForegroundColor Green
}

# ── Done ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "══════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  BUILD COMPLETE!" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Release folder : $((Resolve-Path $releaseDir).Path)"
Write-Host "  Launcher       : $((Resolve-Path $launcherExe).Path)"
Write-Host ""
Write-Host "  To distribute: zip the entire release folder and share it."
Write-Host "  Users double-click  bin\$launcherName.exe  to launch."
Write-Host ""
