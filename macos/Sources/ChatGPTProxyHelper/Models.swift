import Foundation
import Darwin

// MARK: - 代理配置

enum ProxyScheme: String, Codable, CaseIterable, Identifiable, Equatable {
    case http
    case socks5

    var id: String { rawValue }
    var label: String { self == .http ? "HTTP" : "SOCKS5" }
}

struct AppConfig: Codable, Equatable {
    var scheme: ProxyScheme = .http
    var host: String = "127.0.0.1"
    var port: Int = 7897
    var createLauncher: Bool = true
    var injectEnv: Bool = true
    var launchAfter: Bool = true
    var theme: String = "light"
    var enabled: Bool = false

    var proxyURL: String { "\(scheme == .http ? "http" : "socks5")://\(host):\(port)" }
    var proxyServerFlag: String { "--proxy-server=\(proxyURL)" }
}

extension AppConfig {
    /// 首次运行时若常见本地代理端口有监听，自动预填
    static func smartDefault() -> AppConfig {
        var cfg = AppConfig()
        let candidates: [(Int, ProxyScheme)] = [
            (7897, .http), (7890, .http), (1080, .socks5),
            (1087, .http), (8889, .http), (6152, .http), (8118, .http),
        ]
        for (port, scheme) in candidates where PortProbe.isListening(port: port) {
            cfg.port = port
            cfg.scheme = scheme
            break
        }
        return cfg
    }
}

final class ConfigStore {
    static let shared = ConfigStore()

    let dir: URL
    var fileURL: URL { dir.appendingPathComponent("config.json") }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dir = base.appendingPathComponent("ChatGPTProxyHelper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig.smartDefault()
        }
        return cfg
    }

    func save(_ cfg: AppConfig) {
        guard let data = try? JSONEncoder().encode(cfg) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - 运行日志

struct LogLine: Identifiable {
    let id = UUID()
    let time: String
    let text: String
}

final class LogStore {
    static let shared = LogStore()
    private let lock = NSLock()
    let fileURL: URL

    init() {
        fileURL = ConfigStore.shared.dir.appendingPathComponent("manager.log")
    }

    static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    func append(_ message: String) {
        let line = "\(Self.stamp()) \(message)\n"
        lock.lock()
        defer { lock.unlock() }
        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: fileURL.path) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    /// 最近 n 条日志（时间只保留 HH:mm:ss）
    func tail(_ n: Int = 120) -> [LogLine] {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return raw.split(separator: "\n").suffix(n).compactMap { line in
            let s = String(line)
            let time = s.count >= 19 ? String(s.dropFirst(11).prefix(8)) : ""
            let text = s.count > 20 ? String(s.dropFirst(20)) : s
            return LogLine(time: time, text: text)
        }
    }
}

// MARK: - 端口探测

enum PortProbe {
    static func isListening(port: Int, host: String = "127.0.0.1", timeoutMs: Int32 = 400) -> Bool {
        probe(port: port, host: host, timeoutMs: timeoutMs)
    }

    /// 同时探测 IPv4 回环与 IPv6 回环
    static func isListeningAny(port: Int, timeoutMs: Int32 = 400) -> Bool {
        isListening(port: port, host: "127.0.0.1", timeoutMs: timeoutMs)
            || probe(port: port, host: "::1", timeoutMs: timeoutMs)
    }

    private static func probe(port: Int, host: String, timeoutMs: Int32) -> Bool {
        let isIPv6 = host.contains(":")
        let family = isIPv6 ? AF_INET6 : AF_INET
        let fd = socket(family, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var connected: Int32 = -1
        if isIPv6 {
            var addr = sockaddr_in6()
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = in_port_t(port).bigEndian
            inet_pton(AF_INET6, host, &addr.sin6_addr)
            connected = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        } else {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_port = in_port_t(port).bigEndian
            inet_pton(AF_INET, host, &addr.sin_addr)
            connected = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if connected == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pollfdSet = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pollfdSet, 1, timeoutMs) > 0 else { return false }
        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
        return err == 0
    }
}
