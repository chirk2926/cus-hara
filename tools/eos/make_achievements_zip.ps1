# EOS の実績を一括インポートする ZIP を data/titles.json から作る（要件#79, #86, #133）
#   使い方: powershell -ExecutionPolicy Bypass -File tools/eos/make_achievements_zip.ps1
#   出力:   tools/eos/out/achievements_import.zip（開発者ポータル → 実績 → 実績の作成 → 一括インポート）
# 形式: https://dev.epicgames.com/docs/epic-online-services/eos-fundamentals/tools/bulk-importer-exporter-tool
#   stats.csv                    統計 titleT001…（MAX）。ゲームは称号を取ると 1 を送る（scripts/eos_matchmaker.gd）
#   achievementDefinitions.csv   実績 t001…（統計 titleT001 が 1 以上で解除）
#   achievementLocalizations.csv 既定（英語）・ja・zh-Hans・ko の名前と説明、アイコン
#   locked.png / rarity1-5.png   アイコン（仮。ZIP のいちばん上に置く）
# ★ インポートすると、ポータルにある統計・実績の定義はこの内容で置きかわる（プレイヤーの記録は消えない）。
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$out = Join-Path $PSScriptRoot 'out'
$stage = Join-Path $out 'zip'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false

$titles = (Get-Content (Join-Path $root 'data/titles.json') -Raw -Encoding utf8 | ConvertFrom-Json).titles

function Format-Field([string]$s) {
    $s = ($s -replace '\s+', ' ').Trim()
    if ($s -match '[",\r\n]') { return '"' + ($s -replace '"', '""') + '"' }
    return $s
}
function Write-Csv([string]$name, [string[]]$header, $rows) {
    $lines = @(($header -join ','))
    foreach ($r in $rows) { $lines += (($r | ForEach-Object { Format-Field $_ }) -join ',') }
    [IO.File]::WriteAllText((Join-Path $stage $name), ($lines -join "`r`n"), $utf8)
}
function Get-StatName([string]$id) { 'title' + $id.Substring(0, 1).ToUpper() + $id.Substring(1) }

# 統計と実績
$stats = @(); $defs = @(); $locs = @()
$locales = @(@{ tag = ''; key = 'en' }, @{ tag = 'ja'; key = 'ja' }, @{ tag = 'zh-Hans'; key = 'zh' }, @{ tag = 'ko'; key = 'ko' })
foreach ($t in $titles) {
    $id = [string]$t.id
    if ($id -notmatch '^t\d{3}$') { throw "unexpected id: $id" }
    $stat = Get-StatName $id
    $stats += , @($stat, 'MAX')
    $defs += , @($id, 'FALSE', "${stat}:1")
    $rarity = [Math]::Max(1, [Math]::Min(5, [int]$t.rarity))
    foreach ($l in $locales) {
        $name = [string]$t.name.($l.key); $desc = [string]$t.desc.($l.key)
        if ($name -eq '') { $name = [string]$t.name.en }
        if ($desc -eq '') { $desc = [string]$t.desc.en }
        if ($name -eq '' -or $desc -eq '') { throw "missing text: $id $($l.key)" }
        $locs += , @($id, $l.tag, $name, $desc, $name, $desc, '', 'locked.png', "rarity$rarity.png")
    }
}
Write-Csv 'stats.csv' @('name', 'aggregationType') $stats
Write-Csv 'achievementDefinitions.csv' @('name', 'hidden', 'statThresholds') $defs
Write-Csv 'achievementLocalizations.csv' @('name', 'locale', 'lockedTitle', 'lockedDescription', 'unlockedTitle', 'unlockedDescription', 'flavorText', 'lockedIcon', 'unlockedIcon') $locs

# アイコン（仮）: 1024x1024。鍵のかかった灰色と、★の数（レア度）ごとの色
function New-Icon([string]$file, [System.Drawing.Color]$bg, [string]$text, [System.Drawing.Color]$fg) {
    $bmp = New-Object System.Drawing.Bitmap 1024, 1024
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear($bg)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(90, 255, 255, 255)), 40
    $g.DrawEllipse($pen, 112, 112, 800, 800)
    $font = New-Object System.Drawing.Font 'Segoe UI Symbol', 150, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
    $g.DrawString($text, $font, (New-Object System.Drawing.SolidBrush $fg), (New-Object System.Drawing.RectangleF 0, 0, 1024, 1024), $fmt)
    $g.Dispose()
    $bmp.Save((Join-Path $stage $file), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}
New-Icon 'locked.png' ([System.Drawing.Color]::FromArgb(70, 70, 76)) '?' ([System.Drawing.Color]::FromArgb(160, 160, 168))
$colors = @($null, @(120, 144, 156), @(67, 160, 71), @(30, 136, 229), @(142, 36, 170), @(230, 145, 0))
for ($r = 1; $r -le 5; $r++) {
    $c = $colors[$r]
    New-Icon "rarity$r.png" ([System.Drawing.Color]::FromArgb($c[0], $c[1], $c[2])) ([string][char]0x2605 * $r) ([System.Drawing.Color]::White)
}

$zip = Join-Path $out 'achievements_import.zip'
if (Test-Path $zip) { Remove-Item -Force $zip }
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
Write-Output ("{0} titles -> {1}" -f $titles.Count, $zip)
