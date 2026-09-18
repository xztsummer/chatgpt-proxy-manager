# Drag test: activate the target window, then simulate a mouse drag on its title bar.
param([Parameter(Mandatory = $true)][string]$ProcessName)
$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class DragHelper {
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern int GetWindowTextW(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassNameW(IntPtr hWnd, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
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
  public static string Describe(IntPtr h) {
    var t = new StringBuilder(256); GetWindowTextW(h, t, 256);
    var c = new StringBuilder(256); GetClassNameW(h, c, 256);
    uint pid; GetWindowThreadProcessId(h, out pid);
    return "hwnd=" + h + " class=" + c + " pid=" + pid + " title=" + t;
  }
  public static void Drag(int fromX, int fromY, int toX, int toY) {
    SetCursorPos(fromX, fromY);
    System.Threading.Thread.Sleep(250);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(200);
    int steps = 15;
    for (int i = 1; i <= steps; i++) {
      SetCursorPos(fromX + (toX - fromX) * i / steps, fromY + (toY - fromY) * i / steps);
      System.Threading.Thread.Sleep(35);
    }
    System.Threading.Thread.Sleep(200);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(350);
  }
}
"@
foreach ($p in Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) { [void][DragHelper]::Pids.Add([uint32]$p.Id) }
[void][DragHelper]::EnumWindows([DragHelper+EnumProc]{ param($h, $l) [DragHelper]::Collect($h, $l) }, [IntPtr]::Zero)
if ([DragHelper]::Found.Count -eq 0) { Write-Output "no window"; exit 1 }
$hwnd = [DragHelper]::Found[0]
[void][DragHelper]::ShowWindow($hwnd, 9)
# 置顶保证点击落在目标窗口上（HWND_TOPMOST=-1，SWP_NOMOVE|SWP_NOSIZE=0x3）
[void][DragHelper]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x3)
[void][DragHelper]::SetForegroundWindow($hwnd)
Start-Sleep -Milliseconds 800
$before = New-Object DragHelper+RECT
[void][DragHelper]::GetWindowRect($hwnd, [ref]$before)
$cx = [int](($before.Left + $before.Right) / 2)
$cy = $before.Top + 27
Write-Output ("target  : " + [DragHelper]::Describe($hwnd))
Write-Output ("foreground: " + [DragHelper]::Describe([DragHelper]::GetForegroundWindow()))
Write-Output ("before  : " + $before.Left + "," + $before.Top + " " + ($before.Right - $before.Left) + "x" + ($before.Bottom - $before.Top))
[DragHelper]::Drag($cx, $cy, $cx + 140, $cy + 70)
$after = New-Object DragHelper+RECT
[void][DragHelper]::GetWindowRect($hwnd, [ref]$after)
Write-Output ("after   : " + $after.Left + "," + $after.Top + " " + ($after.Right - $after.Left) + "x" + ($after.Bottom - $after.Top))
$dx = $after.Left - $before.Left
$dy = $after.Top - $before.Top
# 取消置顶（HWND_NOTOPMOST=-2）
[void][DragHelper]::SetWindowPos($hwnd, [IntPtr](-2), 0, 0, 0, 0, 0x3)
$verdict = "DRAG FAILED"
if ($dx -ne 0 -or $dy -ne 0) { $verdict = "DRAG OK" }
Write-Output ("moved   : dx=" + $dx + " dy=" + $dy + " -> " + $verdict)

# ---- 缩放测试：拖动右下角边框 ----
[void][DragHelper]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x3)
Start-Sleep -Milliseconds 400
$r0 = New-Object DragHelper+RECT
[void][DragHelper]::GetWindowRect($hwnd, [ref]$r0)
[DragHelper]::Drag($r0.Right - 3, $r0.Bottom - 3, $r0.Right + 90, $r0.Bottom + 70)
$r1 = New-Object DragHelper+RECT
[void][DragHelper]::GetWindowRect($hwnd, [ref]$r1)
[void][DragHelper]::SetWindowPos($hwnd, [IntPtr](-2), 0, 0, 0, 0, 0x3)
$dw = ($r1.Right - $r1.Left) - ($r0.Right - $r0.Left)
$dh = ($r1.Bottom - $r1.Top) - ($r0.Bottom - $r0.Top)
$resizeVerdict = "RESIZE FAILED"
if ($dw -ne 0 -or $dh -ne 0) { $resizeVerdict = "RESIZE OK" }
Write-Output ("resized : dw=" + $dw + " dh=" + $dh + " -> " + $resizeVerdict)
