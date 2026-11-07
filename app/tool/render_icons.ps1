# Render ikon app Remotto dari app/tool/icon/*.svg menjadi PNG.
# Butuh Microsoft Edge atau Google Chrome (headless). Hasil: arsip di app/assets/icon
# (tidak didaftarkan di pubspec), ikon gelap di mipmap Android dan AppIcon iOS.
# Ikon terang hanya diarsipkan. Tidak ada PNG dengan sudut membulat atau alpha.

$ErrorActionPreference = 'Stop'

$appDir = Split-Path -Parent $PSScriptRoot
$iconDir = Join-Path $PSScriptRoot 'icon'
$assetDir = Join-Path $appDir 'assets/icon'
$androidRes = Join-Path $appDir 'android/app/src/main/res'
$iosSet = Join-Path $appDir 'ios/Runner/Assets.xcassets/AppIcon.appiconset'

$browser = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $browser) {
    throw 'Microsoft Edge atau Google Chrome tidak ditemukan. Pasang salah satunya, lalu jalankan ulang.'
}

Add-Type -AssemblyName System.Drawing

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('remotto-icons-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

function Save-IconPng {
    param([string]$SvgName, [int]$Px, [string]$OutPath)

    $svgPath = Join-Path $iconDir $SvgName
    if (-not (Test-Path $svgPath)) { throw "SVG tidak ada: $svgPath" }
    $svg = [IO.File]::ReadAllText($svgPath)
    $html = '<!doctype html><html><head><meta charset="utf-8"><style>' +
        "html,body{margin:0;padding:0;overflow:hidden;background:#000}svg{display:block;width:${Px}px;height:${Px}px}" +
        '</style></head><body>' + $svg + '</body></html>'

    $id = [guid]::NewGuid().ToString('N')
    $htmlPath = Join-Path $tmp "$id.html"
    $shotPath = Join-Path $tmp "$id.png"
    $profile = Join-Path $tmp "$id-profile"
    [IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding $false))

    $url = 'file:///' + ($htmlPath -replace '\\', '/')
    # Edge headless menulis screenshot secara asinkron: tunggu sampai file ada dan ukurannya stabil.
    & $browser --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 `
        "--user-data-dir=$profile" "--screenshot=$shotPath" "--window-size=$Px,$Px" $url *> $null

    $deadline = (Get-Date).AddSeconds(30)
    $lastLen = -1
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $shotPath) {
            $len = (Get-Item $shotPath).Length
            if ($len -gt 0 -and $len -eq $lastLen) { break }
            $lastLen = $len
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not (Test-Path $shotPath)) { throw "Render gagal: $SvgName ${Px}px" }

    $src = [System.Drawing.Bitmap]::FromFile($shotPath)
    try {
        if ($src.Width -ne $Px -or $src.Height -ne $Px) {
            throw "Ukuran screenshot $($src.Width)x$($src.Height), seharusnya ${Px}x${Px}: $SvgName"
        }
        # Salin ke RGB 24-bit: tanpa alpha dan tanpa chunk metadata dari screenshot.
        $dst = New-Object System.Drawing.Bitmap $Px, $Px, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $g = [System.Drawing.Graphics]::FromImage($dst)
        try {
            $g.Clear([System.Drawing.Color]::Black)
            $g.DrawImage($src, 0, 0, $Px, $Px)
        }
        finally { $g.Dispose() }
        $dir = Split-Path -Parent $OutPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        $dst.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $dst.Dispose()
    }
    finally { $src.Dispose() }
    Write-Host "OK $OutPath (${Px}px)"
}

try {
    # Arsip sumber: dark dan light 1024.
    Save-IconPng 'icon-dark.svg' 1024 (Join-Path $assetDir 'app-icon-dark-1024.png')
    Save-IconPng 'icon-light.svg' 1024 (Join-Path $assetDir 'app-icon-light-1024.png')

    # Android launcher: hanya ikon gelap.
    $android = @{ 'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192 }
    foreach ($density in $android.Keys) {
        Save-IconPng 'icon-dark.svg' $android[$density] (Join-Path $androidRes "mipmap-$density/ic_launcher.png")
    }

    # iOS AppIcon: hanya ikon gelap, sesuai Contents.json yang dihasilkan flutter create.
    $ios = [ordered]@{
        'Icon-App-20x20@1x.png' = 20;   'Icon-App-20x20@2x.png' = 40;   'Icon-App-20x20@3x.png' = 60
        'Icon-App-29x29@1x.png' = 29;   'Icon-App-29x29@2x.png' = 58;   'Icon-App-29x29@3x.png' = 87
        'Icon-App-40x40@1x.png' = 40;   'Icon-App-40x40@2x.png' = 80;   'Icon-App-40x40@3x.png' = 120
        'Icon-App-60x60@2x.png' = 120;  'Icon-App-60x60@3x.png' = 180
        'Icon-App-76x76@1x.png' = 76;   'Icon-App-76x76@2x.png' = 152
        'Icon-App-83.5x83.5@2x.png' = 167
        'Icon-App-1024x1024@1x.png' = 1024
    }
    foreach ($name in $ios.Keys) {
        Save-IconPng 'icon-dark.svg' $ios[$name] (Join-Path $iosSet $name)
    }
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
