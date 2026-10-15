<#
.SYNOPSIS
    Baut die Debug- oder Release-APK und installiert sie auf einem oder
    mehreren ausgewaehlten adb-Geraeten.

.DESCRIPTION
    Listet alle Geraete aus `adb devices` (mit Hersteller/Modell, damit man
    sie unterscheiden kann), laesst eines, mehrere oder alle auswaehlen,
    baut die APK per `flutter build apk` und installiert sie nacheinander
    auf jedem gewaehlten Geraet.

.PARAMETER Release
    Release-APK statt Debug bauen/installieren. Signiert mit dem Debug-Key
    (siehe android/app/build.gradle.kts), fuer Tests reicht das.

.PARAMETER SkipBuild
    Zuletzt gebaute APK installieren, ohne neu zu bauen.

.PARAMETER All
    Ohne Nachfrage auf allen verbundenen Geraeten installieren.

.PARAMETER Device
    Ohne Nachfrage auf allen Geraeten installieren, deren Modell, Hersteller
    oder Seriennummer diesen Text enthaelt (z.B. -Device MiTV).

.PARAMETER EnableService
    Schaltet nach der Installation den Hintergrunddienst (Bedienungshilfe)
    per adb ein - praktisch, wenn er im TV-Menue fehlt oder nach einem
    Update deaktiviert wurde. Andere aktive Bedienungshilfen bleiben erhalten.

.PARAMETER Launch
    Startet die App nach der Installation.

.EXAMPLE
    ./scripts/deploy.ps1
.EXAMPLE
    ./scripts/deploy.ps1 -Release -EnableService -Launch
.EXAMPLE
    ./scripts/deploy.ps1 -Release -SkipBuild -All
.EXAMPLE
    ./scripts/deploy.ps1 -Release -Device MiTV
#>
param(
    [switch]$Release,
    [switch]$SkipBuild,
    [switch]$All,
    [string]$Device,
    [switch]$EnableService,
    [switch]$Launch
)

$ErrorActionPreference = 'Stop'
$variant = if ($Release) { 'release' } else { 'debug' }
$package = 'org.lotzapp.home_control'
$serviceComponent = "$package/.PanelAccessibilityService"

function Find-Adb {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:ANDROID_HOME\platform-tools\adb.exe",
        "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    throw "adb.exe nicht gefunden. ANDROID_HOME setzen oder platform-tools in den PATH aufnehmen."
}

function Enable-PanelService([string]$serial) {
    $current = (& $adb -s $serial shell settings get secure enabled_accessibility_services 2>$null | Out-String).Trim()
    if ($current -eq 'null') { $current = '' }
    $entries = @($current -split ':' | Where-Object { $_ -ne '' })
    if ($entries -notcontains $serviceComponent) {
        $entries += $serviceComponent
        & $adb -s $serial shell settings put secure enabled_accessibility_services ($entries -join ':')
    }
    & $adb -s $serial shell settings put secure accessibility_enabled 1
}

$adb = Find-Adb
$repoRoot = Split-Path -Parent $PSScriptRoot
$apkPath = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-$variant.apk"

# --- Geraete ermitteln --------------------------------------------------
$rawDevices = & $adb devices | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne "" }
$serials = @()
foreach ($line in $rawDevices) {
    $parts = $line -split "\s+"
    if ($parts.Length -ge 2 -and $parts[1] -eq "device") {
        $serials += $parts[0]
    }
}

if ($serials.Count -eq 0) {
    Write-Host "Keine adb-Geraete gefunden ('adb devices' zeigt keines im Zustand 'device')." -ForegroundColor Red
    Write-Host "TV-Box per WLAN verbinden:  adb connect <IP>:5555" -ForegroundColor DarkGray
    exit 1
}

Write-Host "Ermittle Geraetenamen..." -ForegroundColor DarkGray
$devices = @()
foreach ($serial in $serials) {
    $model = (& $adb -s $serial shell getprop ro.product.model 2>$null | Out-String).Trim()
    $manufacturer = (& $adb -s $serial shell getprop ro.product.manufacturer 2>$null | Out-String).Trim()
    $devices += [PSCustomObject]@{
        Serial       = $serial
        Manufacturer = $manufacturer
        Model        = $model
    }
}

if ($All) {
    $chosen = $devices
} elseif ($Device) {
    $chosen = @($devices | Where-Object {
        "$($_.Manufacturer) $($_.Model) $($_.Serial)" -like "*$Device*"
    })
} else {
    Write-Host ""
    Write-Host "Verbundene Geraete:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $devices.Count; $i++) {
        $d = $devices[$i]
        Write-Host ("  [{0}] {1} {2}  ({3})" -f ($i + 1), $d.Manufacturer, $d.Model, $d.Serial)
    }
    Write-Host ("  [a] Alle ({0} Geräte)" -f $devices.Count)
    Write-Host ""

    $selection = Read-Host "Auf welche(s) Gerät(e) installieren? (Nummer(n) mit Komma getrennt, oder 'a' für alle)"

    $chosen = @()
    if ($selection.Trim().ToLower() -eq 'a') {
        $chosen = $devices
    } else {
        $indices = $selection -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        foreach ($idx in $indices) {
            $n = 0
            if ([int]::TryParse($idx, [ref]$n) -and $n -ge 1 -and $n -le $devices.Count) {
                $chosen += $devices[$n - 1]
            } else {
                Write-Host "Ungültige Auswahl übersprungen: '$idx'" -ForegroundColor Yellow
            }
        }
    }
}

if ($chosen.Count -eq 0) {
    Write-Host "Keine gültige Auswahl - Abbruch." -ForegroundColor Red
    exit 1
}

# --- Bauen -----------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Host ""
    Write-Host ("Baue {0}-APK..." -f $variant) -ForegroundColor Cyan
    Push-Location $repoRoot
    try {
        & flutter build apk "--$variant"
        if ($LASTEXITCODE -ne 0) { throw "flutter build fehlgeschlagen (exit code $LASTEXITCODE)." }
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path $apkPath)) {
    throw "APK nicht gefunden: $apkPath - erst bauen (ohne -SkipBuild)."
}

# --- Installieren ------------------------------------------------------------
Write-Host ""
foreach ($d in $chosen) {
    Write-Host ("Installiere {0}-APK auf {1} {2} ({3})..." -f $variant, $d.Manufacturer, $d.Model, $d.Serial) -ForegroundColor Cyan
    & $adb -s $d.Serial install -r $apkPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Fehlgeschlagen (exit code $LASTEXITCODE)" -ForegroundColor Red
        continue
    }
    Write-Host "  OK" -ForegroundColor Green

    # Erlaubt der App, ihren Dienst nach Neustart/"Beenden erzwingen" selbst wieder einzuschalten.
    & $adb -s $d.Serial shell pm grant $package android.permission.WRITE_SECURE_SETTINGS
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Autostart-Berechtigung erteilt" -ForegroundColor Green
    } else {
        Write-Host "  Autostart-Berechtigung konnte nicht erteilt werden" -ForegroundColor Yellow
    }

    if ($EnableService) {
        Enable-PanelService $d.Serial
        Write-Host "  Hintergrunddienst eingeschaltet" -ForegroundColor Green
    }
    if ($Launch) {
        & $adb -s $d.Serial shell monkey -p $package -c android.intent.category.LAUNCHER 1 *> $null
        Write-Host "  App gestartet" -ForegroundColor Green
    }
}
