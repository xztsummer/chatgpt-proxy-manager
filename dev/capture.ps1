# Screenshot helper (development-time visual check).
# Modes: window = PrintWindow of the app window, screen = composited screen region (shows Mica).
param(
    [Parameter(Mandatory = $true)][string]$ProcessName,
    [Parameter(Mandatory = $true)][string]$OutPath,
    [switch]$Screen,
    [switch]$TopMost
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class CapHelper {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  public static HashSet<uint> Pids = new HashSet<uint>();
  public static List<IntPtr> Found = new List<IntPtr>();
  public static bool Collect(IntPtr hWnd, IntPtr lParam) {
    uint pid; GetWindowThreadProcessId(hWnd, out pid);
    if (Pids.Contains(pid) && IsWindowVisible(hWnd)) {
      RECT r; GetWindowRect(hWnd, out r);
      if (r.Right - r.Left > 200 && r.Bottom - r.Top > 200) Found.Add(hWnd);
    }
    return true;
  }
}
"@
foreach ($p in Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) {
    [void][CapHelper]::Pids.Add([uint32]$p.Id)
}
[void][CapHelper]::EnumWindows([CapHelper+EnumProc]{ param($h, $l) [CapHelper]::Collect($h, $l) }, [IntPtr]::Zero)
if ([CapHelper]::Found.Count -eq 0) { Write-Output "no visible window for $ProcessName"; exit 1 }
$hwnd = [CapHelper]::Found[0]
if ($TopMost) {
    [void][CapHelper]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x3)
    Start-Sleep -Milliseconds 700
}
$r = New-Object CapHelper+RECT
[void][CapHelper]::GetWindowRect($hwnd, [ref]$r)
$w = $r.Right - $r.Left
$h = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
if ($Screen) {
    $g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
    $mode = 'screen'
}
else {
    $hdc = $g.GetHdc()
    [void][CapHelper]::PrintWindow($hwnd, $hdc, 2)
    $g.ReleaseHdc($hdc)
    $mode = 'window'
}
$g.Dispose()
$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("saved $OutPath ($w x $h) mode=$mode hwnd=$hwnd")
