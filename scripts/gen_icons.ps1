<#
.SYNOPSIS
    Erzeugt alle App-Icons, das TV-Banner und das In-App-Logo aus docs/logo.png
    ("Intelligentes Haus mit Power-Symbol", 1254x1254, App-Kachel mit runden Ecken).

.DESCRIPTION
    - mipmap-*/ic_launcher.png           Kachel mit transparenten Ecken (Android < 8)
    - drawable-nodpi/ic_launcher_foreground.png
                                         Haus fuer das adaptive Icon (Android 8+), im
                                         sicheren Bereich, Rand weich ausgeblendet
    - values/colors.xml                  Hintergrundfarbe des adaptiven Icons
    - drawable-xhdpi/banner.png          TV-Banner 320x180 dp
    - assets/logo.png                    Logo fuer die App-Kopfzeile
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$res = Join-Path $root 'android\app\src\main\res'
$src = [Drawing.Bitmap]::FromFile((Join-Path $root 'docs\logo.png'))
$n = $src.Width

# Kachel (ohne aeusseren Rand) und Haus-Ausschnitt, relativ zur Bildgroesse
$tile = New-Object Drawing.Rectangle ([int]($n * 0.047)), ([int]($n * 0.047)), ([int]($n * 0.907)), ([int]($n * 0.907))
$house = New-Object Drawing.Rectangle ([int]($n * 0.104)), ([int]($n * 0.104)), ([int]($n * 0.792)), ([int]($n * 0.792))

function New-Canvas([int]$w, [int]$h) {
    $bmp = New-Object Drawing.Bitmap($w, $h, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'; $g.TextRenderingHint = 'AntiAliasGridFit'
    return $bmp, $g
}

function RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x, $y, 2 * $r, 2 * $r, 180, 90); $p.AddArc($x + $w - 2 * $r, $y, 2 * $r, 2 * $r, 270, 90)
    $p.AddArc($x + $w - 2 * $r, $y + $h - 2 * $r, 2 * $r, 2 * $r, 0, 90); $p.AddArc($x, $y + $h - 2 * $r, 2 * $r, 2 * $r, 90, 90)
    $p.CloseFigure(); return $p
}

# Kachel mit runden, transparenten Ecken auf ($x,$y) in Groesse $s zeichnen
function Draw-Tile($g, [float]$x, [float]$y, [float]$s) {
    $g.SetClip((RoundRect $x $y $s $s ($s * 0.2)))
    $g.DrawImage($src, (New-Object Drawing.RectangleF $x, $y, $s, $s), $tile, 'Pixel')
    $g.ResetClip()
}

# --- Launcher-Icons fuer Android < 8 ---
$sizes = @{ 'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192 }
foreach ($d in $sizes.Keys) {
    $s = $sizes[$d]
    $bmp, $g = New-Canvas $s $s
    Draw-Tile $g 0 0 $s
    $bmp.Save((Join-Path $res "mipmap-$d\ic_launcher.png"), [Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

# --- Adaptives Icon: Haus im sicheren Bereich (66 von 108 dp), Rand weich ausblenden ---
$fs = 432                    # 108 dp bei xxxhdpi
$inner = [int]($fs * 0.70)   # Haus-Ausschnitt; das Haus selbst fuellt ~88 % davon -> ~62 % = sicherer Bereich
$off = [int](($fs - $inner) / 2)
$bmp, $g = New-Canvas $fs $fs
$g.DrawImage($src, (New-Object Drawing.Rectangle $off, $off, $inner, $inner), $house, 'Pixel')
$g.Dispose()
# Randfarbe des Ausschnitts = Hintergrund des adaptiven Icons
[long]$r = 0; [long]$gr = 0; [long]$b = 0; $cnt = 0
for ($i = 0; $i -lt $inner; $i += 4) {
    $last = $inner - 1
    foreach ($pt in @(@($i, 0), @($i, $last), @(0, $i), @($last, $i))) {
        $c = $bmp.GetPixel($off + $pt[0], $off + $pt[1]); $r += $c.R; $gr += $c.G; $b += $c.B; $cnt++
    }
}
$bg = [Drawing.Color]::FromArgb(255, [int]($r / $cnt), [int]($gr / $cnt), [int]($b / $cnt))
# Weicher Uebergang: aeussere 12 % des Ausschnitts nach aussen transparent
$fade = $inner * 0.12
for ($y = $off; $y -lt $off + $inner; $y++) {
    for ($x = $off; $x -lt $off + $inner; $x++) {
        $edge = [Math]::Min([Math]::Min($x - $off, $off + $inner - 1 - $x), [Math]::Min($y - $off, $off + $inner - 1 - $y))
        if ($edge -lt $fade) {
            $c = $bmp.GetPixel($x, $y)
            $bmp.SetPixel($x, $y, [Drawing.Color]::FromArgb([int](255 * $edge / $fade), $c.R, $c.G, $c.B))
        }
    }
}
New-Item -ItemType Directory -Force (Join-Path $res 'drawable-nodpi') | Out-Null
$bmp.Save((Join-Path $res 'drawable-nodpi\ic_launcher_foreground.png'), [Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$hex = '#{0:X2}{1:X2}{2:X2}' -f $bg.R, $bg.G, $bg.B
@"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- aus scripts/gen_icons.ps1 (Randfarbe des Logos) -->
    <color name="ic_launcher_background">$hex</color>
</resources>
"@ | Set-Content (Join-Path $res 'values\colors.xml') -Encoding utf8

# --- TV-Banner 320x180 dp (xhdpi = 640x360 px) ---
$w = 640; $h = 360
$bmp, $g = New-Canvas $w $h
$g.Clear($bg)
$green = [Drawing.Color]::FromArgb(255, 0x2F, 0x9E, 0x5C)
$g.FillRectangle((New-Object Drawing.SolidBrush $green), 0, $h - 10, $w, 10)
Draw-Tile $g 34 40 270
$font = New-Object Drawing.Font('Segoe UI Semibold', 50, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$small = New-Object Drawing.Font('Segoe UI', 26, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
$g.DrawString('Home', $font, [Drawing.Brushes]::White, 330, 98)
$g.DrawString('Control', $font, (New-Object Drawing.SolidBrush $green), 330, 155)
$g.DrawString('Home Assistant', $small, (New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(160, 255, 255, 255))), 334, 225)
New-Item -ItemType Directory -Force (Join-Path $res 'drawable-xhdpi') | Out-Null
$bmp.Save((Join-Path $res 'drawable-xhdpi\banner.png'), [Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

# --- Logo fuer die App-Kopfzeile ---
$bmp, $g = New-Canvas 192 192
Draw-Tile $g 0 0 192
New-Item -ItemType Directory -Force (Join-Path $root 'assets') | Out-Null
$bmp.Save((Join-Path $root 'assets\logo.png'), [Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

$src.Dispose()
Write-Host "Icons, Banner und Logo erzeugt (Hintergrund $hex)."
