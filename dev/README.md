# 开发期辅助脚本（普通用户不需要）

这些脚本是我在开发和验证界面时用的工具，保留下来方便后续维护和二次开发。
它们都不会修改系统设置（唯一例外见下），都支持通过参数指定目标窗口/文件。

| 脚本 | 用途 |
| --- | --- |
| `capture.ps1` | 截取指定进程的窗口：`-Screen` 抓真实屏幕合成结果（可看到 Mica），默认用 `PrintWindow` 只抓窗口内容 |
| `crop.ps1` | 裁剪并放大截图，便于逐像素检查 UI 细节 |
| `compose.ps1` | 把多张截图横向拼成一张（README 里的浅/深色对比图就是这么生成的） |
| `click.ps1` | 在指定窗口的相对坐标上模拟一次点击（用于验证按钮事件） |
| `test-drag.ps1` | 模拟拖动标题栏与右下角边框，验证无边框窗口的拖动/缩放是否正常 |
| `test-system-theme.ps1` | **注意：会临时修改 Windows 应用主题**（`AppsUseLightTheme`）并广播，用于验证"跟随系统"是否实时生效，用完请自行改回 |

调用示例：

```powershell
# 抓当前浅色主题的窗口内容
powershell -ExecutionPolicy Bypass -File dev\capture.ps1 -ProcessName ChatGPTProxyManager -OutPath dev\shot.png

# 抓真实屏幕合成结果（含 Mica 材质），并临时置顶避免被遮挡
powershell -ExecutionPolicy Bypass -File dev\capture.ps1 -ProcessName ChatGPTProxyManager -OutPath dev\shot-screen.png -Screen -TopMost
```

> 调试界面时，"像素级抽查"比肉眼更可靠：`capture.ps1` 抓到的 `PrintWindow` 结果不包含 DWM 圆角与 Mica，
> 涉及背景/材质一致性判断时请用 `-Screen` 抓真实合成结果。
