# 编译 ChatGPT 代理助手（使用 Windows 自带 csc + .NET Framework 4.8，无需安装任何 SDK）
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$srcDir = Join-Path $root 'src'
$distDir = Join-Path $root 'dist'
if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }

# 1) 源码统一写为 UTF-8 BOM，避免 csc 按本地代码页解析中文
foreach ($name in @('Core.cs', 'MainWindow.cs', 'Program.cs', 'MainWindow.xaml', 'ThemeLight.xaml', 'ThemeDark.xaml')) {
    $path = Join-Path $srcDir $name
    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($true)))
}

# 2) 图标
$icon = Join-Path $srcDir 'app.ico'
if (-not (Test-Path $icon)) {
    & (Join-Path $PSScriptRoot 'make-icon.ps1') -OutPath $icon | Out-Null
}

# 3) 编译
$fw = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319'
$csc = Join-Path $fw 'csc.exe'
if (-not (Test-Path $csc)) { throw "找不到 csc.exe：$csc" }

$refs = @(
    (Join-Path $fw 'System.dll'),
    (Join-Path $fw 'System.Core.dll'),
    (Join-Path $fw 'System.Xml.dll'),
    (Join-Path $fw 'System.Management.dll'),
    (Join-Path $fw 'System.Xaml.dll'),
    (Join-Path $fw 'WPF\WindowsBase.dll'),
    (Join-Path $fw 'WPF\PresentationCore.dll'),
    (Join-Path $fw 'WPF\PresentationFramework.dll')
)
foreach ($r in $refs) { if (-not (Test-Path $r)) { throw "缺少引用程序集：$r" } }

$out = Join-Path $distDir 'ChatGPTProxyManager.exe'
$arguments = @(
    '/nologo',
    '/target:winexe',
    '/platform:anycpu',
    '/optimize+',
    '/codepage:65001',
    ('/out:' + $out),
    ('/win32icon:' + $icon),
    ('/win32manifest:' + (Join-Path $srcDir 'app.manifest')),
    ('/resource:' + (Join-Path $srcDir 'MainWindow.xaml') + ',MainWindow.xaml'),
    ('/resource:' + (Join-Path $srcDir 'ThemeLight.xaml') + ',ThemeLight.xaml'),
    ('/resource:' + (Join-Path $srcDir 'ThemeDark.xaml') + ',ThemeDark.xaml'),
    ('/reference:' + ($refs -join ';')),
    (Join-Path $srcDir 'Core.cs'),
    (Join-Path $srcDir 'MainWindow.cs'),
    (Join-Path $srcDir 'Program.cs')
)

& $csc $arguments
if ($LASTEXITCODE -ne 0) { throw "编译失败，退出码 $LASTEXITCODE" }

$size = [Math]::Round((Get-Item $out).Length / 1KB, 1)
Write-Output ("编译成功: " + $out + " (" + $size + " KB)")
