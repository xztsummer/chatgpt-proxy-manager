import SwiftUI
import AppKit

// MARK: - 检测与状态模型

struct DetectionItem: Identifiable {
    let id: Int
    let label: String
    let value: String
    /// true=绿点 false=红点 nil=灰点
    let ok: Bool?
}

struct HeroChip {
    let ok: Bool
    let text: String
}

struct HeroStatus {
    var tint: Color
    var symbol: String
    var solid = false
    var title: String
    var desc: String
    var chips: [HeroChip] = []
}

// MARK: - 应用状态

@MainActor
final class AppState: ObservableObject {
    @Published var config: AppConfig
    @Published var detections: [DetectionItem] = []
    @Published var hero = HeroStatus(tint: Palette.blue, symbol: "bolt.circle",
                                     title: "正在检测…", desc: "正在读取本机环境，请稍候。")
    @Published var logs: [LogLine] = []
    @Published var testOK: Bool?
    @Published var testResult: String?
    @Published var testing = false
    @Published var launching = false
    @Published var busy = false

    private let store = ConfigStore.shared

    init(preview: Bool = false) {
        config = preview ? AppConfig() : store.load()
        if preview {
            config.enabled = true
            detections = Self.sampleDetections(config: config)
            hero = Self.makeHero(config: config, app: ChatGPTAppInfo(path: "/Applications/ChatGPT.app",
                                                                     version: "26.915.31029",
                                                                     installKind: "App Store"),
                                 portListener: ("verge-mihomo", 15780),
                                 systemProxyEnabled: false, tunActive: false,
                                 launcherInstalled: true, running: true,
                                 runningProxy: "http://127.0.0.1:7897")
            logs = Self.sampleLogs()
            testOK = true
            testResult = "成功 · 236ms"
        } else {
            logs = LogStore.shared.tail()
            LogStore.shared.append("助手已启动（v\(AppVersion.string)）")
        }
    }

    // MARK: 通用

    func log(_ message: String) {
        LogStore.shared.append(message)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logs.append(LogLine(time: formatter.string(from: Date()), text: message))
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }
    }

    func persistConfig() {
        store.save(config)
    }

    func setTheme(_ theme: AppTheme) {
        config.theme = theme.rawValue
    }

    func copyLogs() {
        let text = logs.map { "\($0.time) \($0.text)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        log("运行日志已复制到剪贴板")
    }

    // MARK: 检测

    func refresh(logMessage: String? = nil) async {
        if let logMessage { log(logMessage) }
        let cfg = config
        let snapshot = await Task.detached(priority: .userInitiated) { () -> ([DetectionItem], HeroStatus) in
            let app = ChatGPTApp.locate()
            let listener = Diagnostics.portListener(port: cfg.port)
            let systemProxy = Diagnostics.systemProxy()
            let tun = Diagnostics.tunActive()
            let launcherInstalled = Launcher.isInstalled()
            let running = ChatGPTApp.isRunning()
            let runningProxy = running ? ChatGPTApp.runningProxyServer() : nil
            let items = Self.makeDetections(config: cfg, app: app, portListener: listener,
                                            systemProxyEnabled: systemProxy.enabled, tunActive: tun,
                                            launcherInstalled: launcherInstalled,
                                            running: running, runningProxy: runningProxy)
            let hero = Self.makeHero(config: cfg, app: app, portListener: listener,
                                     systemProxyEnabled: systemProxy.enabled, tunActive: tun,
                                     launcherInstalled: launcherInstalled,
                                     running: running, runningProxy: runningProxy)
            return (items, hero)
        }.value
        detections = snapshot.0
        hero = snapshot.1
    }

    nonisolated static func makeDetections(config: AppConfig, app: ChatGPTAppInfo?,
                                           portListener: (name: String, pid: Int)?,
                                           systemProxyEnabled: Bool, tunActive: Bool,
                                           launcherInstalled: Bool,
                                           running: Bool, runningProxy: String?) -> [DetectionItem] {
        let runState: (value: String, ok: Bool?) = {
            guard running else { return ("未运行", nil) }
            guard let runningProxy else { return ("运行中 · 未走代理（点「启动 ChatGPT」重启）", false) }
            if runningProxy == config.proxyURL { return ("运行中 · 已走本地代理", true) }
            return ("运行中 · 走的是其他代理 \(runningProxy)", false)
        }()
        return [
            DetectionItem(id: 0, label: "ChatGPT 应用",
                          value: app.map { "\($0.version) · \($0.installKind) · \(($0.path as NSString).lastPathComponent)" } ?? "未找到（需安装到「应用程序」）",
                          ok: app != nil),
            DetectionItem(id: 1, label: "代理端口",
                          value: portListener.map { listener in
                              let pidText = listener.pid > 0 ? " (PID \(listener.pid))" : ""
                              return "\(config.host):\(config.port) · \(listener.name)\(pidText)"
                          } ?? "\(config.host):\(config.port) · 未监听",
                          ok: portListener != nil),
            DetectionItem(id: 2, label: "系统代理",
                          value: systemProxyEnabled ? "已开启（本工具无需它）" : "已关闭（无需开启）",
                          ok: true),
            DetectionItem(id: 3, label: "TUN / VPN",
                          value: tunActive ? "已启用（本工具无需它）" : "未启用（无需开启）",
                          ok: true),
            DetectionItem(id: 4, label: "启动配置",
                          value: config.enabled ? "已就绪 · \(config.proxyServerFlag)\(config.injectEnv ? " + 环境变量" : "")" : "未开启",
                          ok: config.enabled ? true : nil),
            DetectionItem(id: 5, label: "启动器",
                          value: launcherInstalled ? "已创建 · \(Launcher.installURL.path)" : "未创建",
                          ok: launcherInstalled ? true : nil),
            DetectionItem(id: 6, label: "运行状态", value: runState.value, ok: runState.ok),
        ]
    }

    nonisolated static func makeHero(config: AppConfig, app: ChatGPTAppInfo?,
                                     portListener: (name: String, pid: Int)?,
                                     systemProxyEnabled: Bool, tunActive: Bool,
                                     launcherInstalled: Bool,
                                     running: Bool, runningProxy: String?) -> HeroStatus {
        guard let app else {
            return HeroStatus(tint: Palette.red, symbol: "exclamationmark.triangle.fill",
                              title: "未找到 ChatGPT 应用",
                              desc: "请先将 ChatGPT 桌面版安装到「应用程序」文件夹，然后点击「环境检测」右上角的刷新按钮。",
                              chips: [HeroChip(ok: false, text: "ChatGPT 未安装")])
        }
        guard portListener != nil else {
            return HeroStatus(tint: Palette.amber, symbol: "wifi.exclamationmark",
                              title: "代理端口不可达",
                              desc: "本地 \(config.host):\(config.port) 没有进程在监听。请确认代理客户端正在运行，或修改上方代理地址后重新检测。",
                              chips: [
                                  HeroChip(ok: true, text: "ChatGPT \(app.version)"),
                                  HeroChip(ok: false, text: "代理端口未监听"),
                                  HeroChip(ok: config.enabled, text: config.enabled ? "已开启" : "未开启"),
                              ])
        }
        let appChip = HeroChip(ok: true, text: "ChatGPT \(app.version) · \(app.installKind)")
        let portChip = HeroChip(ok: true, text: "代理端口正常")
        if config.enabled {
            return HeroStatus(tint: Palette.green, symbol: "checkmark", solid: true,
                              title: "代理已就绪",
                              desc: "从启动器、Dock 或下方按钮启动 ChatGPT，流量将经 \(config.proxyURL) 转发，全程无需开启系统代理或 TUN 模式。",
                              chips: [appChip, portChip,
                                      HeroChip(ok: true, text: launcherInstalled ? "启动器已创建" : "启动配置完成")])
        }
        return HeroStatus(tint: Palette.blue, symbol: "bolt.circle",
                          title: "就绪，一键开启",
                          desc: "以启动参数方式让 ChatGPT 桌面版走本地代理，系统代理与 TUN 全程无需开启，随时可一键还原。",
                          chips: [appChip, portChip, HeroChip(ok: false, text: "未开启")])
    }

    // MARK: 动作

    func enableAll() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }

        guard let app = ChatGPTApp.locate() else {
            log("未找到 ChatGPT 应用，请先安装到「应用程序」文件夹")
            await refresh()
            return
        }
        config.enabled = true
        persistConfig()
        log("已写入启动配置：\(config.proxyServerFlag)\(config.injectEnv ? "（含环境变量注入）" : "")")
        log("提示：应用内「检查更新」由 Sparkle 走系统网络，不经过本代理；需要更新时请临时开启系统代理")

        if config.createLauncher {
            do {
                try Launcher.create(helperPath: Bundle.main.executableURL?.path ?? CommandLine.arguments[0],
                                    iconSource: FileManager.default.fileExists(atPath: app.iconPath) ? app.iconPath : nil)
                log("已创建启动器：\(Launcher.installURL.path)")
            } catch {
                log("创建启动器失败：\(error.localizedDescription)")
            }
        }
        if config.launchAfter {
            await launchChatGPT()
        }
        await refresh()
    }

    func restoreAll() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }

        Launcher.remove()
        config.enabled = false
        persistConfig()
        log("已还原：启动器与启动配置已移除（ChatGPT 本体未做任何改动）")
        await refresh()
    }

    func launchChatGPT() async {
        guard !launching else { return }
        guard let app = ChatGPTApp.locate() else {
            log("未找到 ChatGPT 应用，请先安装到「应用程序」文件夹")
            await refresh()
            return
        }
        launching = true
        defer { launching = false }

        if ChatGPTApp.isRunning() {
            if ChatGPTApp.runningWithProxy(config.proxyURL) {
                ChatGPTApp.activate()
                log("ChatGPT 已在运行且已走本地代理，直接置前")
                return
            }
            log("检测到 ChatGPT 正在运行（未走当前代理），先退出…")
            let quit = await ChatGPTApp.quitAll()
            log(quit ? "已退出 ChatGPT" : "退出超时，已强制结束进程")
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        do {
            try ChatGPTApp.launch(info: app, config: config)
            log("已启动 ChatGPT：\(config.proxyServerFlag)\(config.injectEnv ? " · 环境变量已注入" : "")")
        } catch {
            log("启动失败：\(error.localizedDescription)")
            return
        }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        await refresh()
    }

    func testConnectivity() async {
        guard !testing else { return }
        testing = true
        defer { testing = false }

        log("正在测试连通性：\(config.proxyURL) → chatgpt.com:443 …")
        let outcome = await Connectivity.test(config: config)
        testOK = outcome.ok
        testResult = outcome.ok
            ? ("成功" + (outcome.ms.map { " · \($0)ms" } ?? ""))
            : outcome.message
        log(outcome.ok
            ? "连通性测试通过：\(config.proxyURL) → chatgpt.com:443 · \(outcome.ms ?? 0)ms · \(outcome.message)"
            : "连通性测试失败：\(outcome.message)")
    }

    // MARK: 预览样例

    nonisolated static func sampleDetections(config: AppConfig) -> [DetectionItem] {
        makeDetections(config: config,
                       app: ChatGPTAppInfo(path: "/Applications/ChatGPT.app", version: "26.915.31029", installKind: "App Store"),
                       portListener: ("verge-mihomo", 15780),
                       systemProxyEnabled: false, tunActive: false,
                       launcherInstalled: true, running: true,
                       runningProxy: "http://127.0.0.1:7897")
    }

    nonisolated static func sampleLogs() -> [LogLine] {
        [("15:32:53", "助手已启动（v1.0.0）"),
         ("15:32:54", "开始检测环境"),
         ("15:32:55", "检测完成：ChatGPT 26.915.31029 · App Store"),
         ("15:33:02", "已写入启动配置：--proxy-server=http://127.0.0.1:7897（含环境变量注入）"),
         ("15:33:02", "已创建启动器：/Applications/ChatGPT（代理）.app"),
         ("15:33:05", "已启动 ChatGPT：--proxy-server=http://127.0.0.1:7897 · 环境变量已注入")].map {
            LogLine(time: $0.0, text: $0.1)
        }
    }
}

// MARK: - 入口 App

enum AppVersion {
    static let string = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
}

struct ChatGPTProxyHelperApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("ChatGPT 代理助手") {
            ContentView()
                .environmentObject(state)
                .preferredColorScheme(AppTheme(rawValue: state.config.theme)?.colorScheme)
                .frame(minWidth: 940, idealWidth: 1020, minHeight: 620, idealHeight: 730)
                .task { await state.refresh(logMessage: "开始检测环境") }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
