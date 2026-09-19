import Foundation
import CFNetwork

struct ConnTestOutcome {
    var ok: Bool
    var message: String
    var ms: Int?
}

enum Connectivity {
    /// 经本地代理请求 https://chatgpt.com/robots.txt，收到任何 HTTP 响应即视为打通
    static func test(config: AppConfig, timeout: TimeInterval = 8) async -> ConnTestOutcome {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout

        var proxyDictionary: [String: Any] = [:]
        switch config.scheme {
        case .http:
            proxyDictionary[kCFNetworkProxiesHTTPEnable as String] = true
            proxyDictionary[kCFNetworkProxiesHTTPProxy as String] = config.host
            proxyDictionary[kCFNetworkProxiesHTTPPort as String] = config.port
            proxyDictionary[kCFNetworkProxiesHTTPSEnable as String] = true
            proxyDictionary[kCFNetworkProxiesHTTPSProxy as String] = config.host
            proxyDictionary[kCFNetworkProxiesHTTPSPort as String] = config.port
        case .socks5:
            proxyDictionary[kCFNetworkProxiesSOCKSEnable as String] = true
            proxyDictionary[kCFNetworkProxiesSOCKSProxy as String] = config.host
            proxyDictionary[kCFNetworkProxiesSOCKSPort as String] = config.port
        }
        configuration.connectionProxyDictionary = proxyDictionary

        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        guard let url = URL(string: "https://chatgpt.com/robots.txt") else {
            return ConnTestOutcome(ok: false, message: "URL 无效", ms: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let start = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            return ConnTestOutcome(ok: true, message: "HTTP \(statusCode)", ms: elapsed)
        } catch {
            return ConnTestOutcome(ok: false, message: error.localizedDescription, ms: nil)
        }
    }
}
