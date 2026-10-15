<#
.SYNOPSIS
    Erzeugt App-Icon (PNG je Dichte) und TV-Banner aus demselben Motiv wie
    res/drawable/ic_launcher_foreground.xml: gruenes Haus mit amberfarbenem
    Power-Symbol auf dunklem Grund (Farben wie home_radio).
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$res = Join-Path (Split-Path -Parent $PSScriptRoot) 'android\app\src\main\res'

$bg = [Drawing.Color]::FromArgb(255, 0x14, 0x1A, 0x22)
$green = [Drawing.Color]::FromArgb(255, 0x2F, 0x9E, 0x5C)
$amber = [Drawing.Color]::FromArgb(255, 0xFF, 0xB3, 0x00)

# Motiv im 108er-Raster (wie das adaptive Icon), Ursprung ($ox,$oy), Faktor $k
function Draw-Logo($g, [double]$ox, [double]$oy, [double]$k) {
    function P([double]$x, [double]$y) { New-Object Drawing.PointF(($ox + $x * $k), ($oy + $y * $k)) }
    $house = [Drawing.PointF[]]@((P 54 24), (P 87 53), (P 78 53), (P 78 84), (P 30 84), (P 30 53), (P 21 53))
    $g.FillPolygon((New-Object Drawing.SolidBrush $green), $house)
    # dunkler Kreis im Haus
    $r = 14
    $g.FillEllipse((New-Object Drawing.SolidBrush $bg), [float]($ox + (54 - $r) * $k), [float]($oy + (66 - $r) * $k), [float](2 * $r * $k), [float](2 * $r * $k))
    # Power-Symbol
    $pen = New-Object Drawing.Pen($amber, [float](3.6 * $k))
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $a = 8.5
    $g.DrawArc($pen, [float]($ox + (54 - $a) * $k), [float]($oy + (67 - $a) * $k), [float](2 * $a * $k), [float](2 * $a * $k), -50, 280)
    $g.DrawLine($pen, (P 54 56), (P 54 66))
}

function New-Canvas([int]$w, [int]$h) {
    $bmp = New-Object Drawing.Bitmap($w, $h)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
    return $bmp, $g
}

function Fill-RoundRect($g, $brush, [float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x, $y, 2 * $r, 2 * $r, 180, 90); $p.AddArc($x + $w - 2 * $r, $y, 2 * $r, 2 * $r, 270, 90)
    $p.AddArc($x + $w - 2 * $r, $y + $h - 2 * $r, 2 * $r, 2 * $r, 0, 90); $p.AddArc($x, $y + $h - 2 * $r, 2 * $r, 2 * $r, 90, 90)
    $p.CloseFigure(); $g.FillPath($brush, $p)
}

# --- Launcher-Icons (aeltere Android-Versionen; ab 8.0 adaptives Vektor-Icon) ---
$sizes = @{ 'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192 }
foreach ($d in $sizes.Keys) {
    $s = $sizes[$d]
    $bmp, $g = New-Canvas $s $s
    Fill-RoundRect $g (New-Object Drawing.SolidBrush $bg) 0 0 $s $s ($s * 0.22)
    # 108er-Motiv mittig, sicherer Bereich ~ 72/108 der Kante
    $k = $s / 80.0
    Draw-Logo $g ($s / 2 - 54 * $k) ($s / 2 - 54 * $k) $k
    $bmp.Save((Join-Path $res "mipmap-$d\ic_launcher.png"), [Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

# --- TV-Banner 320x180 dp (xhdpi = 640x360 px) ---
$w = 640; $h = 360
$bmp, $g = New-Canvas $w $h
$g.Clear($bg)
$g.FillRectangle((New-Object Drawing.SolidBrush $green), 0, $h - 10, $w, 10)
$k = 2.6
Draw-Logo $g (34 - 20 * $k) ($h / 2 - 56 * $k) $k
$font = New-Object Drawing.Font('Segoe UI Semibold', 50, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$small = New-Object Drawing.Font('Segoe UI', 26, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
$g.DrawString('Home', $font, [Drawing.Brushes]::White, 300, 105)
$g.DrawString('Control', $font, (New-Object Drawing.SolidBrush $green), 300, 162)
$g.DrawString('Home Assistant', $small, (New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(160, 255, 255, 255))), 304, 232)
New-Item -ItemType Directory -Force (Join-Path $res 'drawable-xhdpi') | Out-Null
$bmp.Save((Join-Path $res 'drawable-xhdpi\banner.png'), [Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host 'Icons und Banner erzeugt.'
