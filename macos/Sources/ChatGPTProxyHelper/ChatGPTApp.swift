import Foundation
import AppKit

struct ChatGPTAppInfo {
    var path: String
    var version: String
    var installKind: String

    var execPath: String { path + "/Contents/MacOS/ChatGPT" }
    var iconPath: String { path + "/Contents/Resources/icon-chatgpt.icns" }
}

enum ChatGPTApp {
    static let bundleID = "com.openai.codex"
    static let candidatePaths = [
        "/Applications/ChatGPT.app",
        NSHomeDirectory() + "/Applications/ChatGPT.app",
    ]

    static func locate() -> ChatGPTAppInfo? {
        for path in candidatePaths where FileManager.default.fileExists(atPath: path + "/Contents/Info.plist") {
            guard let plist = NSDictionary(contentsOfFile: path + "/Contents/Info.plist"),
                  (plist["CFBundleIdentifier"] as? String) == bundleID else { continue }
            let version = (plist["CFBundleShortVersionString"] as? String) ?? "?"
            let isMAS = FileManager.default.fileExists(atPath: path + "/Contents/_MASReceipt/receipt")
            return ChatGPTAppInfo(path: path, version: version, installKind: isMAS ? "App Store" : "DMG 安装")
        }
        return nil
    }

    // MARK: - 进程状态

    static func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
    }

    /// 解析 ps 输出里属于 ChatGPT（Codex Framework）的进程
    private static func matchingProcessLines() -> [(pid: Int, args: String)] {
        let out = Shell.output("/bin/ps", ["-axo", "pid=,args="])
        var result: [(Int, String)] = []
        for line in out.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.contains("Codex Framework") || s.contains("/ChatGPT.app/Contents/MacOS/ChatGPT") else { continue }
            guard let pid = Int(s.split(separator: " ", maxSplits: 1).first.map(String.init) ?? "") else { continue }
            let args = String(s.drop(while: { !$0.isWhitespace }))
            result.append((pid, args))
        }
        return result
    }

    static func mainPIDs() -> [Int] {
        matchingProcessLines()
            .filter { !$0.args.contains("--type=") && !$0.args.contains("crashpad") && !$0.args.contains("Helper") }
            .map(\.pid)
    }

    static func frameworkPIDs() -> [Int] {
        matchingProcessLines().filter { !$0.args.contains("crashpad") }.map(\.pid)
    }

    static func isRunning() -> Bool {
        !runningApps().isEmpty || !frameworkPIDs().isEmpty
    }

    /// 运行中的 ChatGPT 正在使用的 --proxy-server 值（无则返回 nil）
    static func runningProxyServer() -> String? {
        for (_, args) in matchingProcessLines() where args.contains("--proxy-server") {
            if let range = args.range(of: "--proxy-server=") {
                let value = args[range.upperBound...].prefix(while: { !$0.isWhitespace })
                if !value.isEmpty { return String(value) }
            }
        }
        return nil
    }

    static func runningWithProxy() -> Bool {
        runningProxyServer() != nil
    }

    /// 是否正以指定代理地址运行
    static func runningWithProxy(_ proxyURL: String) -> Bool {
        runningProxyServer() == proxyURL
    }

    static func activate() {
        for app in runningApps() {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [])
            }
        }
    }

    /// 退出 ChatGPT：先 SIGTERM 主进程让 Chromium 保存会话，超时再强杀
    @discardableResult
    static func quitAll(timeout: TimeInterval = 8) async -> Bool {
        for app in runningApps() { app.terminate() }
        for pid in mainPIDs() { kill(pid_t(pid), SIGTERM) }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if mainPIDs().isEmpty { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard !mainPIDs().isEmpty else { return true }

        for app in runningApps() { app.forceTerminate() }
        for pid in frameworkPIDs() { kill(pid_t(pid), SIGTERM) }
        try? await Task.sleep(nanoseconds: 800_000_000)
        for pid in frameworkPIDs() { kill(pid_t(pid), SIGKILL) }
        try? await Task.sleep(nanoseconds: 300_000_000)
        return mainPIDs().isEmpty
    }

    // MARK: - 启动

    enum LaunchError: LocalizedError {
        case openFailed(String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let message): return "open 启动失败：\(message)"
            }
        }
    }

    private static let openSupportsEnv: Bool = {
        Shell.run("/usr/bin/open", ["--help"]).out.contains("--env")
    }()

    static func launch(info: ChatGPTAppInfo, config: AppConfig) throws {
        let flag = config.proxyServerFlag

        if config.injectEnv && !openSupportsEnv {
            // 旧版 open 不支持 --env：直接 exec 主程序并注入环境变量
            let process = Process()
            process.executableURL = URL(fileURLWithPath: info.execPath)
            process.arguments = [flag]
            var environment = ProcessInfo.processInfo.environment
            environment["HTTP_PROXY"] = config.proxyURL
            environment["HTTPS_PROXY"] = config.proxyURL
            environment["ALL_PROXY"] = config.proxyURL
            environment["NO_PROXY"] = "localhost,127.0.0.1,::1"
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            return
        }

        var args = [info.path]
        if config.injectEnv && openSupportsEnv {
            for pair in ["HTTP_PROXY=\(config.proxyURL)",
                         "HTTPS_PROXY=\(config.proxyURL)",
                         "ALL_PROXY=\(config.proxyURL)",
                         "NO_PROXY=localhost,127.0.0.1,::1"] {
                args += ["--env", pair]
            }
        }
        args += ["--args", flag]
        let (code, message) = Shell.run("/usr/bin/open", args)
        guard code == 0 else { throw LaunchError.openFailed(message) }
    }
}
