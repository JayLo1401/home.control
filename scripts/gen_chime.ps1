<#
.SYNOPSIS
    Erzeugt den Tuerglocken-Gong (Ding-Dong) als WAV:
    android/app/src/main/res/raw/doorbell.wav

.DESCRIPTION
    Synthetischer Glockenklang (Grundton + unharmonische Obertoene,
    exponentielles Abklingen): E5 "Ding", dann C5 "Dong". 44,1 kHz, 16 Bit, mono.
#>
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$out = Join-Path $repoRoot 'android\app\src\main\res\raw\doorbell.wav'

$rate = 44100
$length = 2.8
$n = [int]($rate * $length)
$samples = New-Object double[] $n

# (Startzeit s, Grundfrequenz Hz)
$notes = @(@(0.0, 659.25), @(0.65, 523.25))
# Glockenartige Teiltoene: (Frequenzfaktor, Lautstaerke, Abklingrate)
$partials = @(@(1.0, 1.0, 2.2), @(2.0, 0.35, 3.5), @(2.76, 0.25, 4.5), @(5.4, 0.08, 7.0))

foreach ($note in $notes) {
    $start = [int]($note[0] * $rate)
    $f0 = $note[1]
    for ($i = $start; $i -lt $n; $i++) {
        $t = ($i - $start) / $rate
        $attack = [Math]::Min(1.0, $t / 0.004)
        $v = 0.0
        foreach ($p in $partials) {
            $v += $p[1] * [Math]::Exp(-$t * $p[2]) * [Math]::Sin(2 * [Math]::PI * $f0 * $p[0] * $t)
        }
        $samples[$i] += $attack * $v
    }
}

$peak = ($samples | ForEach-Object { [Math]::Abs($_) } | Measure-Object -Maximum).Maximum
$gain = 0.85 * 32767 / $peak
# Sanft ausblenden (letzte 0,3 s)
$fade = [int](0.3 * $rate)

New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
$fs = [IO.File]::Create($out)
$w = New-Object IO.BinaryWriter($fs)
$dataBytes = $n * 2
$w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $dataBytes))
$w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1)
$w.Write([int]$rate); $w.Write([int]($rate * 2)); $w.Write([int16]2); $w.Write([int16]16)
$w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]$dataBytes)
for ($i = 0; $i -lt $n; $i++) {
    $env = if ($i -gt $n - $fade) { ($n - $i) / $fade } else { 1.0 }
    $w.Write([int16][Math]::Round($samples[$i] * $gain * $env))
}
$w.Close()
Write-Host "Geschrieben: $out ($([Math]::Round((Get-Item $out).Length / 1KB)) KB)"
