import Foundation

enum Shell {
    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> (code: Int32, out: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    static func output(_ launchPath: String, _ args: [String]) -> String {
        run(launchPath, args).out
    }
}
