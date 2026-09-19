import Foundation

/// 「ChatGPT（代理）」启动器：一个指向本工具 --launch 的轻量 .app，
/// 让用户从启动台 / 应用程序文件夹双击即得以代理方式启动 ChatGPT（原应用保持不动）。
enum Launcher {
    static var installURL: URL { URL(fileURLWithPath: "/Applications/ChatGPT（代理）.app") }
    static let bundleID = "local.chatgptproxy.helper.launcher"

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: installURL.path + "/Contents/Info.plist")
    }

    static func create(helperPath: String, iconSource: String?) throws {
        let fm = FileManager.default
        let root = installURL
        if isInstalled() { try? fm.removeItem(at: root) }

        let contents = root.appendingPathComponent("Contents", isDirectory: true)
        let macOSDir = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try fm.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        let script = """
        #!/bin/bash
        HELPER="\(helperPath)"
        if [ -x "$HELPER" ]; then
          exec "$HELPER" --launch
        else
          exec /usr/bin/open -b local.chatgptproxy.helper --args --launch
        fi
        """
        let scriptURL = macOSDir.appendingPathComponent("launcher")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        if let iconSource, fm.fileExists(atPath: iconSource) {
            try? fm.copyItem(atPath: iconSource, toPath: resources.appendingPathComponent("ChatGPT.icns").path)
        }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let plist: [String: Any] = [
            "CFBundleName": "ChatGPT（代理）",
            "CFBundleDisplayName": "ChatGPT（代理）",
            "CFBundleIdentifier": bundleID,
            "CFBundleVersion": version,
            "CFBundleShortVersionString": version,
            "CFBundleExecutable": "launcher",
            "CFBundleIconFile": "ChatGPT",
            "CFBundlePackageType": "APPL",
            "LSMinimumSystemVersion": "13.0",
            "NSHighResolutionCapable": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
    }

    /// 仅当目标确实是本工具创建的启动器时才删除
    static func remove() {
        guard let plist = NSDictionary(contentsOfFile: installURL.path + "/Contents/Info.plist"),
              (plist["CFBundleIdentifier"] as? String) == bundleID else { return }
        try? FileManager.default.removeItem(at: installURL)
    }
}
