# 裁剪 PNG 的指定区域，便于放大检查 UI 细节
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$OutPath,
    [Parameter(Mandatory = $true)][int]$X,
    [Parameter(Mandatory = $true)][int]$Y,
    [Parameter(Mandatory = $true)][int]$Width,
    [Parameter(Mandatory = $true)][int]$Height,
    [double]$Scale = 1.0
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile($Path)
try {
    $w = [int]($Width * $Scale)
    $h = [int]($Height * $Scale)
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)),
        (New-Object System.Drawing.Rectangle($X, $Y, $Width, $Height)), [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output ("cropped -> $OutPath ($w x $h)")
}
finally { $src.Dispose() }
