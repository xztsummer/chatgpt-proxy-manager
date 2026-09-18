# 生成程序图标（渐变圆角方块 + 双向箭头），输出多尺寸 .ico
param(
    [string]$OutPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\app.ico'),
    [string]$PreviewPath = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function New-GlyphBitmap([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $d = [double]$size * 0.44
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($size - $d, 0, $d, $d, 270, 90)
    $path.AddArc($size - $d, $size - $d, $d, $d, 0, 90)
    $path.AddArc(0, $size - $d, $d, $d, 90, 90)
    $path.CloseFigure()

    $rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.Color]::FromArgb(255, 79, 140, 255),
        [System.Drawing.Color]::FromArgb(255, 139, 92, 246),
        45.0)
    $g.FillPath($grad, $path)

    $white = [System.Drawing.Color]::White
    $brush = New-Object System.Drawing.SolidBrush($white)
    $pen = New-Object System.Drawing.Pen($white, [float]([Math]::Max(1.0, $size * 0.08)))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

    # 上方箭头（向右）
    $g.DrawLine($pen, [float]($size * 0.24), [float]($size * 0.38), [float]($size * 0.60), [float]($size * 0.38))
    $g.FillPolygon($brush, @(
            (New-Object System.Drawing.PointF([float]($size * 0.78), [float]($size * 0.38))),
            (New-Object System.Drawing.PointF([float]($size * 0.58), [float]($size * 0.27))),
            (New-Object System.Drawing.PointF([float]($size * 0.58), [float]($size * 0.49)))
        ))
    # 下方箭头（向左）
    $g.DrawLine($pen, [float]($size * 0.76), [float]($size * 0.62), [float]($size * 0.40), [float]($size * 0.62))
    $g.FillPolygon($brush, @(
            (New-Object System.Drawing.PointF([float]($size * 0.22), [float]($size * 0.62))),
            (New-Object System.Drawing.PointF([float]($size * 0.42), [float]($size * 0.51))),
            (New-Object System.Drawing.PointF([float]($size * 0.42), [float]($size * 0.73)))
        ))

    $g.Dispose()
    return $bmp
}

# 把位图编码成 ICO 里使用的 BMP 数据块并写入文件，返回字节数
function Save-BmpIconPart([System.Drawing.Bitmap]$bmp, [string]$path) {
    $w = $bmp.Width
    $h = $bmp.Height
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([int]40)
    $bw.Write([int]$w)
    $bw.Write([int]($h * 2))
    $bw.Write([int16]1)
    $bw.Write([int16]32)
    $bw.Write([int]0)
    $bw.Write([int]($w * $h * 4))
    $bw.Write([int]0)
    $bw.Write([int]0)
    $bw.Write([int]0)
    $bw.Write([int]0)
    for ($y = $h - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $w; $x++) {
            $c = $bmp.GetPixel($x, $y)
            $bw.Write([byte]$c.B)
            $bw.Write([byte]$c.G)
            $bw.Write([byte]$c.R)
            $bw.Write([byte]$c.A)
        }
    }
    $rowBytes = [int]([Math]::Ceiling($w / 32.0) * 4)
    $mask = New-Object byte[] ($rowBytes * $h)
    $bw.Write($mask, 0, $mask.Length)
    $bw.Flush()
    $bytes = $ms.ToArray()
    [System.IO.File]::WriteAllBytes($path, $bytes)
    $bw.Close()
    $ms.Close()
    return $bytes.Length
}

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$workDir = Join-Path $env:TEMP ('iconparts_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workDir | Out-Null

$parts = New-Object System.Collections.ArrayList
foreach ($s in $sizes) {
    $bmp = New-GlyphBitmap $s
    $partFile = Join-Path $workDir ("part_{0}.bin" -f $s)
    # 全部使用 BMP 编码：Windows 自带的 csc 图标解析器不支持 PNG 压缩条目
    $len = Save-BmpIconPart $bmp $partFile
    [void]$parts.Add([pscustomobject]@{ Size = $s; File = $partFile; Length = $len })
    if ($s -eq 256 -and $PreviewPath) { $bmp.Save($PreviewPath, [System.Drawing.Imaging.ImageFormat]::Png) }
    $bmp.Dispose()
}

$dir = Split-Path -Parent $OutPath
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

$fs = [System.IO.File]::Create($OutPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([int16]0)
$bw.Write([int16]1)
$bw.Write([int16]$parts.Count)
$offset = 6 + 16 * $parts.Count
foreach ($p in $parts) {
    $dim = 0
    if ($p.Size -lt 256) { $dim = $p.Size }
    $bw.Write([byte]$dim)
    $bw.Write([byte]$dim)
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Write([int16]1)
    $bw.Write([int16]32)
    $bw.Write([int]$p.Length)
    $bw.Write([int]$offset)
    $offset += [int]$p.Length
}
foreach ($p in $parts) {
    $bytes = [System.IO.File]::ReadAllBytes($p.File)
    $bw.Write($bytes, 0, $bytes.Length)
}
$bw.Flush()
$bw.Close()
$fs.Close()

Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Output ("图标已生成: " + $OutPath + " (" + $parts.Count + " 个尺寸, " + (Get-Item $OutPath).Length + " 字节)")
