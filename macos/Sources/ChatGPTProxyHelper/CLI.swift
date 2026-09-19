import Foundation
import AppKit
import SwiftUI

enum AppVersionHolder {}

enum CLI {
    static let helpText: String = {
        """
        ChatGPT 代理助手 for macOS v\(AppVersion.string)

        让 ChatGPT 桌面版走本地代理启动，无需开启系统代理或 TUN 模式。
        原理：以 --proxy-server=<本地代理> 启动参数启动 ChatGPT（macOS 版为 Chromium 内核），
        流量仅经由该启动参数走本机代理，不修改系统代理、不创建虚拟网卡。

        用法：
          --detect                        检测环境（应用 / 代理端口 / 系统代理 / TUN / 配置 / 启动器 / 运行状态）
          --test [--host H] [--port P] [--scheme http|socks5]
                                          测试本地代理到 chatgpt.com:443 的连通性
          --enable [--host H] [--port P] [--scheme http|socks5]
                                          写入启动配置，并按当前选项创建启动器
          --launch                        按当前配置以本地代理启动 ChatGPT
          --restore                       一键还原（移除启动器与启动配置，原应用不受影响）
          --render-preview <目录>          渲染 UI 预览图（调试用）
          --help                          显示本帮助

        配置文件：~/Library/Application Support/ChatGPTProxyHelper/config.json
        运行日志：~/Library/Application Support/ChatGPTProxyHelper/manager.log
        """
    }()

    static func run(_ args: [String]) -> Never {
        let command = args.first ?? "--help"
        switch command {
        case "--help", "-h":
            print(helpText)
            exit(0)
        case "--detect":
            print(detectText())
            exit(0)
        default:
            break
        }
        runAsyncThenExit { await handle(command: command, args: Array(args.dropFirst())) }
    }

    /// CLI 需要异步能力（连通性测试、退出 ChatGPT 等）：
    /// 启动一个不显示窗口的 NSApplication 事件循环，在主线程 Actor 上执行完即退出。
    static func runAsyncThenExit(_ action: @escaping () async -> Int32) -> Never {
        NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let delegate = CLIDelegate(action: action)
        NSApp.delegate = delegate
        NSApp.run()
        exit(0)
    }

    @MainActor
    static func handle(command: String, args: [String]) async -> Int32 {
        var config = ConfigStore.shared.load()
        var index = 0
        while index < args.count {
            switch args[index] {
            case "--host":
                index += 1
                if index < args.count { config.host = args[index] }
            case "--port":
                index += 1
                if index < args.count { config.port = Int(args[index]) ?? config.port }
            case "--scheme":
                index += 1
                if index < args.count, let scheme = ProxyScheme(rawValue: args[index].lowercased()) {
                    config.scheme = scheme
                }
            default:
                break
            }
            index += 1
        }
        // 命令行临时覆盖只用于本次动作，不落盘

        switch command {
        case "--test":
            let outcome = await Connectivity.test(config: config)
            if outcome.ok {
                print("✅ 连通性正常 · \(config.proxyURL) → chatgpt.com:443 · \(outcome.ms ?? 0)ms · \(outcome.message)")
                return 0
            }
            print("❌ 连通性失败 · \(config.proxyURL) → chatgpt.com:443 · \(outcome.message)")
            return 1

        case "--launch":
            return await launch(config: config)

        case "--enable":
            config.enabled = true
            ConfigStore.shared.save(config)
            print("✅ 已写入启动配置：\(config.proxyServerFlag)\(config.injectEnv ? "（含环境变量注入）" : "")")
            if config.createLauncher {
                do {
                    let app = ChatGPTApp.locate()
                    let icon = app.map { $0.iconPath }
                    try Launcher.create(helperPath: Bundle.main.executableURL?.path ?? CommandLine.arguments[0],
                                        iconSource: (icon.flatMap { FileManager.default.fileExists(atPath: $0) ? icon : nil }) ?? nil)
                    print("✅ 已创建启动器：\(Launcher.installURL.path)")
                } catch {
                    print("⚠️ 创建启动器失败：\(error.localizedDescription)")
                }
            }
            if config.launchAfter {
                return await launch(config: config)
            }
            return 0

        case "--restore":
            Launcher.remove()
            config.enabled = false
            ConfigStore.shared.save(config)
            print("✅ 已还原：启动器与启动配置已移除（ChatGPT 本体未做任何改动）")
            return 0

        case "--render-preview":
            if let dir = args.first(where: { !$0.hasPrefix("--") }) {
                await RenderSupport.renderPreviews(dir: dir)
                return 0
            }
            print("用法：--render-preview <输出目录>")
            return 2

        default:
            print(helpText)
            return 2
        }
    }

    @MainActor
    static func launch(config: AppConfig) async -> Int32 {
        guard let app = ChatGPTApp.locate() else {
            print("❌ 未找到 ChatGPT 应用（/Applications/ChatGPT.app）")
            return 1
        }
        if ChatGPTApp.isRunning() {
            if ChatGPTApp.runningWithProxy(config.proxyURL) {
                ChatGPTApp.activate()
                print("ℹ️ ChatGPT 已在运行且已走本地代理，已置前")
                return 0
            }
            print("ℹ️ ChatGPT 正在运行（未走当前代理），先退出…")
            _ = await ChatGPTApp.quitAll()
        }
        do {
            try ChatGPTApp.launch(info: app, config: config)
            print("✅ 已启动 ChatGPT · \(config.proxyServerFlag)\(config.injectEnv ? " · 环境变量已注入" : "")")
            return 0
        } catch {
            print("❌ 启动失败：\(error.localizedDescription)")
            return 1
        }
    }

    static func detectText() -> String {
        let config = ConfigStore.shared.load()
        let app = ChatGPTApp.locate()
        let listener = Diagnostics.portListener(port: config.port)
        let systemProxy = Diagnostics.systemProxy()
        let tun = Diagnostics.tunActive()
        let items = AppState.makeDetections(config: config, app: app, portListener: listener,
                                            systemProxyEnabled: systemProxy.enabled, tunActive: tun,
                                            launcherInstalled: Launcher.isInstalled(),
                                            running: ChatGPTApp.isRunning(),
                                            runningProxy: ChatGPTApp.isRunning() ? ChatGPTApp.runningProxyServer() : nil)
        let hero = AppState.makeHero(config: config, app: app, portListener: listener,
                                     systemProxyEnabled: systemProxy.enabled, tunActive: tun,
                                     launcherInstalled: Launcher.isInstalled(),
                                     running: ChatGPTApp.isRunning(),
                                     runningProxy: ChatGPTApp.isRunning() ? ChatGPTApp.runningProxyServer() : nil)
        var lines: [String] = []
        lines.append("ChatGPT 代理助手 · 环境检测")
        lines.append("当前状态：\(hero.title) — \(hero.desc)")
        lines.append(String(repeating: "-", count: 56))
        for item in items {
            let dot = item.ok == true ? "●" : (item.ok == false ? "✖" : "○")
            lines.append("\(dot) \(item.label)：\(item.value)")
        }
        return lines.joined(separator: "\n")
    }
}

final class CLIDelegate: NSObject, NSApplicationDelegate {
    private let action: () async -> Int32

    init(action: @escaping () async -> Int32) {
        self.action = action
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let code = await self.action()
            exit(code)
        }
    }
}

// MARK: - UI 预览离屏渲染（视觉验收用）
// 使用 NSHostingView + cacheDisplay 离屏自绘（不需要屏幕录制权限，且能正确渲染 NSTextField /
// NSSegmentedControl 等 AppKit 控件——ImageRenderer 对它们会渲染成占位黄块）。

enum RenderSupport {
    @MainActor
    static func renderPreviews(dir: String) async {
        let state = AppState(preview: true)
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let cases: [(String, String, ColorScheme)] = [
            ("theme-light", "light", .light),
            ("theme-dark", "dark", .dark),
        ]
        for (name, themeName, scheme) in cases {
            state.config.theme = themeName
            Palette.appearanceOverride = scheme

            let view = VStack(spacing: 0) {
                TitleBarView()
                MainContent()
            }
            .environmentObject(state)
            .environment(\.colorScheme, scheme)
            .frame(width: 1020, alignment: .top)
            .background(Palette.window)

            let hosting = NSHostingView(rootView: view)
            hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            hosting.frame = NSRect(x: 0, y: 0, width: 1020, height: 200)
            hosting.layoutSubtreeIfNeeded()
            let naturalHeight = hosting.fittingSize.height
            hosting.frame = NSRect(x: 0, y: 0, width: 1020, height: max(400, min(naturalHeight, 1600)))
            hosting.layoutSubtreeIfNeeded()

            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                print("渲染失败（无法创建位图）：\(name)")
                continue
            }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                print("渲染失败（PNG 编码）：\(name)")
                continue
            }
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            try? png.write(to: url)
            print("已渲染：\(url.path)（\(rep.pixelsWide)x\(rep.pixelsHigh)）")
        }
        Palette.appearanceOverride = nil
    }
}
