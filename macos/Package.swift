// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChatGPTProxyHelper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ChatGPTProxyHelper",
            path: "Sources/ChatGPTProxyHelper"
        )
    ]
)
