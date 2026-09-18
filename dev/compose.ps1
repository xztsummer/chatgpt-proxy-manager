# 把多张截图横向拼成一张（用于 README 展示）
param(
    [Parameter(Mandatory = $true)][string[]]$Inputs,
    [Parameter(Mandatory = $true)][string]$OutPath,
    [double]$Scale = 1.0,
    [int]$Gap = 16,
    [string]$Background = '#FFFFFFFF'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$images = @()
foreach ($p in $Inputs) { $images += [System.Drawing.Image]::FromFile($p) }
try {
    $w = 0; $h = 0
    foreach ($img in $images) {
        $w += [int]($img.Width * $Scale)
        $h = [Math]::Max($h, [int]($img.Height * $Scale))
    }
    $w += $Gap * ($images.Count - 1)
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.Clear([System.Drawing.ColorTranslator]::FromHtml($Background))
    $x = 0
    foreach ($img in $images) {
        $iw = [int]($img.Width * $Scale)
        $ih = [int]($img.Height * $Scale)
        $g.DrawImage($img, $x, 0, $iw, $ih)
        $x += $iw + $Gap
    }
    $g.Dispose()
    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output ("composed -> $OutPath ($w x $h)")
}
finally { foreach ($img in $images) { $img.Dispose() } }
