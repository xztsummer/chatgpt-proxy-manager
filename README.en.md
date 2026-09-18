# ChatGPT Proxy Assistant

[中文](README.md) | **English**

**Launch the ChatGPT desktop app through your local proxy — no more system proxy, no more TUN mode.**

A single-file Windows utility (~460 KB) with no runtime to install, and light / dark / follow-system themes.

[![Release](https://img.shields.io/github/v/release/xztsummer/chatgpt-proxy-manager?label=download&style=flat-square&color=4f8cff)](../../releases/latest)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%2F%2011-4f8cff?style=flat-square)](#requirements)
[![.NET](https://img.shields.io/badge/dependency-built--in%20.NET%20Framework%204.8-8b5cf6?style=flat-square)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-3ddc97?style=flat-square)](LICENSE)

<img src="docs/themes.png" alt="Light and dark themes" width="900">

---

## The pain point

If `chatgpt.com` is not directly reachable on your network, the ChatGPT desktop app **cannot finish starting** — it just sits on the splash screen and spins. So before every use you have to do one of these:

- Open Clash Verge (or similar) and turn on **system proxy** — but that is a *global* setting: your intranet, VPN and every other app get routed through it too, and things break in confusing ways;
- Or turn on **TUN mode** — which needs administrator rights, installs a virtual network adapter, and frequently fights with VPN clients, Docker or Hyper-V virtual networks;
- And you always forget to turn it off again: forgot to enable → ChatGPT won't start; forgot to disable → other apps misbehave.

In short: **you change the whole system's networking just to run one app.**

## Why "just set an environment variable" doesn't work

The ChatGPT desktop app is an MSIX package (`OpenAI.Codex`) that contains **two network stacks**:

| Component | Network stack | Which proxy setting it honours |
| --- | --- | --- |
| Chromium / Electron shell (the UI) | Chromium networking | **Only the Windows system proxy or the `--proxy-server` launch switch** — it ignores `HTTP_PROXY` |
| Bundled Rust / Node parts (model & session traffic) | their own HTTP clients | `HTTP_PROXY` / `HTTPS_PROXY` environment variables |

Measured behaviour: with environment variables only, the Rust side does reach the API (the model list is fetched), but **the UI still hangs on the splash screen**, because the Chromium half keeps connecting directly.

And MSIX packaged-app shortcuts **cannot carry launch arguments**. That is the real reason people are forced to use the system proxy or TUN mode.

## The approach

1. **Launch the packaged app with arguments.** Bypass the shortcut limitation by calling the COM activation
   interface `IApplicationActivationManager::ActivateApplication` and hand
   `--proxy-server=http://127.0.0.1:7897` to Chromium. Package identity is preserved, so sign-in,
   notifications and auto-update keep working.
2. **Cover the other half with environment variables.** Write user-level `HTTP_PROXY` / `HTTPS_PROXY` /
   `ALL_PROXY` / `NO_PROXY` for the bundled Rust / Node components.
3. **Turn the launcher into the shortcut.** All ChatGPT shortcuts point at this program, which performs the
   steps above silently when started with `--launch` — so "double-click ChatGPT" *is* "start ChatGPT proxied".
4. **Wrap it in a reversible GUI.** Environment detection, one-click enable, one-click restore, an editable
   proxy address and a real connectivity test — with a revert path for every change.

### How it compares

| Approach | Scope | Admin rights | Driver / service | Daily cost |
| --- | --- | --- | --- | --- |
| System proxy | **Global** (all apps) | No | No | Toggle by hand every time |
| TUN mode | **Global** (network layer) | Yes | Yes (virtual adapter) | Toggle by hand; often conflicts with VPNs/VMs |
| Proxifier-style per-process proxy | Selected processes | Yes | Yes (network filter driver) | Rule maintenance |
| **This tool** | **ChatGPT only** | No | No | Configure once, then use the shortcut normally |

## Features

| Feature | Details |
| --- | --- |
| 🚀 **One-click enable** | Writes the env vars, creates a "ChatGPT (Local Proxy)" shortcut, takes over the desktop shortcut (original backed up) and optionally launches ChatGPT — configuration takes under a second, ~2–3 s including app startup |
| ♻️ **One-click restore** | Removes the env vars, deletes the shortcuts it created and restores the original ChatGPT shortcut — back to the pre-install state |
| 🔍 **Environment detection** | Seven live checks: ChatGPT version & install type, which process owns the proxy port, system proxy, TUN, env vars, shortcuts, app running state |
| 🌐 **Editable proxy + real test** | Host/port are editable and remembered; "Test connectivity" performs an HTTP `CONNECT` to `chatgpt.com:443` instead of merely probing the port |
| 🎨 **Three themes** | Light (default) / dark / follow system; the choice is remembered and live-follows Windows theme changes |
| 🖥️ **Native-feeling UI** | Borderless window with Windows 11 Mica material, custom title bar and icon; light theme uses a uniform canvas with soft card shadows |
| 📜 **Run log** | Every action is logged, one-click copy, history kept in `manager.log` — no guessing when diagnosing |
| ⌨️ **CLI switches** | `--launch` / `--enable` / `--restore` / `--test` / `--detect` for scripting or integration |
| 🪶 **Zero dependencies** | ~460 KB, one exe, compiled with the in-box `csc.exe` — no .NET SDK, no Python, no third-party libraries |
| 🔄 **Survives app updates** | Resolves the MSIX package identity and install path dynamically — a Store update of ChatGPT needs no changes |

## Screenshots

**Light theme (default)**

![Light theme](docs/theme-light.png)

**Dark theme**

![Dark theme](docs/theme-dark.png)

**Follow system**

![Follow system](docs/theme-system.png)

## Quick start

1. Download `ChatGPTProxyManager.exe` from [Releases](../../releases/latest) (single file, no installer);
2. Run it, confirm the proxy address (default `127.0.0.1:7897`, the usual mixed port of Clash Verge / mihomo)
   and press **Test connectivity** until it reports "available";
3. Press **One-click enable**. A "ChatGPT (Local Proxy)" shortcut appears on the desktop, and your existing
   "ChatGPT" shortcut is repointed to this program (the original is backed up automatically);
4. From now on just double-click **ChatGPT** — **no system proxy or TUN needed**.

> Windows SmartScreen may warn about an unknown publisher (the exe is not code-signed): choose
> "More info" → "Run anyway". If you prefer, build it yourself from source — the build is reproducible
> from this repository.

### Requirements

- Windows 10 19041+ or Windows 11 (x64)
- .NET Framework 4.8 — **included with** Windows 10 1903+ and Windows 11
- A running local proxy client (Clash Verge / mihomo / sing-box / v2rayN …) listening on a local
  HTTP/mixed port
- The ChatGPT desktop app installed (Microsoft Store MSIX package `OpenAI.Codex`)

### Uninstall / revert

Press **One-click restore** inside the app first (removes env vars, deletes the created shortcuts, restores
the original shortcut), then delete `%LOCALAPPDATA%\ChatGPTProxyManager`. The tool installs no service,
no driver, and never touches your proxy client's configuration.

## FAQ

**Do I have to use Clash Verge?**
No. Any client listening on a local HTTP/mixed port works — just edit the proxy address in the UI
(e.g. `127.0.0.1:7890`).

**After enabling, git / npm also go through the proxy. Is that intended?**
Yes, deliberately: those env vars are meant for CLI tools. If you don't want that, untick
"Set command-line environment variables HTTP(S)_PROXY" in the options and enable again — ChatGPT itself
still uses the proxy via the launch argument.

**My pinned taskbar icon still opens the un-proxied app.**
Taskbar pins point at the original application and cannot be rewritten by third-party programs.
Unpin it and pin the "ChatGPT (Local Proxy)" shortcut instead.

**Does it modify my proxy client?**
No. It only writes user-level environment variables and creates shortcuts. System proxy and TUN stay
disabled — you can see their state in the detection panel.

**Do I need to reconfigure after ChatGPT updates from the Store?**
No. The package identity and install path are resolved dynamically on every start.

**Is this some kind of hack? Is it safe?**
All of the logic lives in this repository: a single executable with no driver and no service. It writes
user-level environment variables, creates/restores shortcuts and starts the app through a documented
Windows COM interface. Every action it takes is visible in the run log.

## Command line

All switches run headless and log to `%LOCALAPPDATA%\ChatGPTProxyManager\manager.log`:

```powershell
ChatGPTProxyManager.exe --detect     # print environment detection results
ChatGPTProxyManager.exe --test       # test proxy connectivity (exit 0 = ok, 2 = failed)
ChatGPTProxyManager.exe --enable     # one-click enable
ChatGPTProxyManager.exe --restore    # one-click restore
ChatGPTProxyManager.exe --launch     # silently start ChatGPT proxied (used by shortcuts)
```

## How it works

```
ChatGPTProxyManager.exe
├── detect   read the MSIX package repository in the registry → identity / version / install path
│            (no PowerShell, no admin); read netstat for the port owner, the registry for the system
│            proxy, and enumerate adapters to spot TUN
├── enable   write HKCU\Environment env vars + broadcast WM_SETTINGCHANGE
│            create/take over shortcuts via WScript.Shell, pointing at this exe with --launch
│            start the packaged app with --proxy-server via IApplicationActivationManager
├── attach   restore and foreground the app window (handles minimized/tray states)
└── restore  undo step by step; env vars are only removed when their value equals what this tool set,
             so your own settings are never overwritten
```

- Stack: C# 5 + WPF (XAML loaded at runtime via `XamlReader`) + the in-box `csc.exe`. **No third-party dependencies.**
- Themes: two palette dictionaries (`src/ThemeLight.xaml` / `src/ThemeDark.xaml`) referenced through
  `DynamicResource`; switching swaps one merged dictionary and takes effect instantly.
- Window: `WindowChrome` borderless + Windows 11 Mica + custom title bar. The light theme uses a uniform
  opaque canvas with depth expressed by card shadows and hairline borders (a deliberate choice after
  hitting a rendering pitfall — see the note in `dev/README.md`).

## Project layout & build

```
src/
  Core.cs            detection, env vars, shortcuts, COM activation, proxy test, enable/restore, themes
  MainWindow.cs      UI controller (events, state refresh, theme switching, animations)
  MainWindow.xaml    layout & styles (loaded at runtime)
  ThemeLight.xaml    light palette        ThemeDark.xaml   dark palette
  Program.cs         entry point and CLI switches
  app.manifest       per-monitor DPI awareness, Windows 10/11 compatibility
build/
  build.ps1          one-shot compile (re-encodes sources as UTF-8 BOM, generates the icon if missing)
  install.ps1        install to %LOCALAPPDATA%
  make-icon.ps1      generate the multi-size .ico icon
dev/                 development helpers (screenshots, pixel probes, synthetic clicks) — see dev/README.md
docs/                screenshots used by the README
```

Build (uses the in-box `csc.exe`, no .NET SDK required):

```powershell
powershell -ExecutionPolicy Bypass -File build\build.ps1     # outputs dist\ChatGPTProxyManager.exe
powershell -ExecutionPolicy Bypass -File build\install.ps1   # install to %LOCALAPPDATA%
```

## Scope and known limitations

- Targets the **ChatGPT desktop app (MSIX package `OpenAI.Codex`)**. The same "activate with arguments"
  trick can be ported to other MSIX-packaged Electron apps by adjusting the package-name matching.
- Requires the proxy client to be running; when the port is not listening the tool says so explicitly
  instead of letting ChatGPT hang.
- The exe is not code-signed, so SmartScreen will warn on first run.
- Not affiliated with OpenAI in any way; it only drives the publicly installed desktop app.
- Developed and verified on Windows 11 (build 26200) with Clash Verge Rev (mihomo, mixed port 7897) and
  the ChatGPT desktop app 26.908.4834. Other clients/versions should work the same — feedback welcome.

## License

[MIT](LICENSE)
