# 安装：把编译好的程序复制到 %LOCALAPPDATA%（快捷方式指向的就是这个位置）
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'dist\ChatGPTProxyManager.exe'
if (-not (Test-Path $source)) { throw "找不到 $source，请先运行 build\build.ps1" }

$targetDir = Join-Path $env:LOCALAPPDATA 'ChatGPTProxyManager'
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
$target = Join-Path $targetDir 'ChatGPTProxyManager.exe'

Get-Process ChatGPTProxyManager -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
Copy-Item $source $target -Force

$readme = Join-Path $root 'README.md'
if (Test-Path $readme) { Copy-Item $readme $targetDir -Force }

Write-Output ("已安装: " + $target)
Write-Output "提示：双击桌面/开始菜单的「ChatGPT（本地代理）」即可使用；若快捷方式尚未创建，运行程序后点击「一键开启」。"
