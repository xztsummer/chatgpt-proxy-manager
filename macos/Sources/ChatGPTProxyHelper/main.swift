import Foundation

// 带命令行参数时进入 CLI 模式（--detect / --test / --enable / --launch / --restore …），否则启动 GUI。
let cliArgs = Array(CommandLine.arguments.dropFirst())
if let first = cliArgs.first, first.hasPrefix("-") {
    CLI.run(cliArgs)
}

ChatGPTProxyHelperApp.main()
