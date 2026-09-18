# Click helper: raise the target window, click at a window-relative coordinate, then restore Z-order.
param(
    [Parameter(Mandatory = $true)][string]$ProcessName,
    [Parameter(Mandatory = $true)][int]$Dx,
    [Parameter(Mandatory = $true)][int]$Dy,
    [switch]$DoubleClick
)
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class ClickHelper {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
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
  public static void Click(int x, int y, int count) {
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(250);
    for (int i = 0; i < count; i++) {
      mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
      System.Threading.Thread.Sleep(60);
      mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
      if (i + 1 < count) System.Threading.Thread.Sleep(80);
    }
    System.Threading.Thread.Sleep(250);
  }
}
"@
foreach ($p in Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) { [void][ClickHelper]::Pids.Add([uint32]$p.Id) }
[void][ClickHelper]::EnumWindows([ClickHelper+EnumProc]{ param($h, $l) [ClickHelper]::Collect($h, $l) }, [IntPtr]::Zero)
if ([ClickHelper]::Found.Count -eq 0) { Write-Output "no window"; exit 1 }
$hwnd = [ClickHelper]::Found[0]
[void][ClickHelper]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x3)
Start-Sleep -Milliseconds 500
$r = New-Object ClickHelper+RECT
[void][ClickHelper]::GetWindowRect($hwnd, [ref]$r)
$clickCount = 1
if ($DoubleClick) { $clickCount = 2 }
[ClickHelper]::Click($r.Left + $Dx, $r.Top + $Dy, $clickCount)
[void][ClickHelper]::SetWindowPos($hwnd, [IntPtr](-2), 0, 0, 0, 0, 0x3)
Write-Output ("clicked at window-relative (" + $Dx + "," + $Dy + ") on window at " + $r.Left + "," + $r.Top + " size " + ($r.Right - $r.Left) + "x" + ($r.Bottom - $r.Top))
