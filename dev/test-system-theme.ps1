# 临时切换 Windows 应用主题并广播，用于验证「跟随系统」是否实时生效
param([Parameter(Mandatory = $true)][int]$Light)   # 1 = 浅色, 0 = 深色
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ThemeBroadcast {
  [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
  public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, string lParam,
      uint flags, uint timeout, out IntPtr result);
  public static void Broadcast() {
    IntPtr r;
    SendMessageTimeout(new IntPtr(0xffff), 0x001A, IntPtr.Zero, "ImmersiveColorSet", 0x0002, 3000, out r);
    SendMessageTimeout(new IntPtr(0xffff), 0x001A, IntPtr.Zero, "Environment", 0x0002, 3000, out r);
  }
}
"@
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -Value $Light -Type DWord
[ThemeBroadcast]::Broadcast()
Write-Output ("AppsUseLightTheme 已设为 " + $Light + " 并已广播")
