import Foundation

struct SystemProxyInfo {
    var enabled: Bool
    var summary: String
}

enum Diagnostics {
    /// 读取 macOS 系统代理（scutil --proxy）
    static func systemProxy() -> SystemProxyInfo {
        let out = Shell.output("/usr/sbin/scutil", ["--proxy"])
        func value(_ key: String) -> String {
            for line in out.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, parts[0] == key { return parts[1] }
            }
            return ""
        }
        func number(_ key: String) -> Int { Int(value(key)) ?? 0 }

        let httpEnabled = number("HTTPEnable") == 1
        let httpsEnabled = number("HTTPSEnable") == 1
        let socksEnabled = number("SOCKSEnable") == 1
        let host = value("HTTPSProxy").isEmpty ? value("HTTPProxy") : value("HTTPSProxy")
        let port = number("HTTPSPort") != 0 ? number("HTTPSPort") : number("HTTPPort")

        if httpEnabled || httpsEnabled {
            let detail = host.isEmpty ? "" : " · http://\(host):\(port)"
            return SystemProxyInfo(enabled: true, summary: "已开启\(detail)（本工具无需它）")
        }
        if socksEnabled {
            return SystemProxyInfo(enabled: true, summary: "已开启 · SOCKS（本工具无需它）")
        }
        return SystemProxyInfo(enabled: false, summary: "已关闭（无需开启）")
    }

    /// 默认路由是否落在 utun 接口（TUN 模式 / 全局 VPN）
    static func defaultInterface() -> String {
        let out = Shell.output("/sbin/route", ["-n", "get", "default"])
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "interface" { return parts[1] }
        }
        return ""
    }

    static func tunActive() -> Bool {
        defaultInterface().hasPrefix("utun")
    }

    /// 指定端口的监听进程（名称 + PID）
    /// 注意：当代理客户端以 root 服务运行（如 Clash Verge 的特权模式）时，
    /// 非特权 lsof 看不到其 socket，此时回退到 TCP 探测 + ps 进程名识别。
    static func portListener(port: Int) -> (name: String, pid: Int)? {
        let out = Shell.output("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"])
        for line in out.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard columns.count >= 2, let pid = Int(columns[1]) else { continue }
            let command = Shell.output("/bin/ps", ["-p", "\(pid)", "-o", "comm="])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (command as NSString).lastPathComponent
            return (name, pid)
        }

        guard PortProbe.isListeningAny(port: port) else { return nil }

        let keywords = ["mihomo", "clash", "sing-box", "xray", "v2ray", "hysteria", "trojan",
                        "gost", "ss-local", "shadowsocks", "leaf", "surge", "quantumult", "tuic"]
        let processes = Shell.output("/bin/ps", ["-axo", "pid=,comm="])
        for line in processes.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard let pid = Int(s.split(separator: " ", maxSplits: 1).first.map(String.init) ?? "") else { continue }
            let lowercased = s.lowercased()
            guard let keyword = keywords.first(where: { lowercased.contains($0) }),
                  !lowercased.contains("chatgptproxyhelper") else { continue }
            _ = keyword
            let command = Shell.output("/bin/ps", ["-p", "\(pid)", "-o", "comm="])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ((command as NSString).lastPathComponent, pid)
        }
        return ("未知进程", 0)
    }
}
