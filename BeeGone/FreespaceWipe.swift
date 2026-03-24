import Foundation

enum FreespaceLevel: Int, CaseIterable, Identifiable {
    case zero = 0
    case random = 1
    case sevenPass = 2
    case gutmann = 3
    case dod = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .zero: "Zero fill (1-pass)"
        case .random: "Random (1-pass)"
        case .sevenPass: "Secure (7-pass)"
        case .gutmann: "Gutmann (35-pass)"
        case .dod: "DoD (3-pass)"
        }
    }
}

enum FreespaceWiper {
    static func wipe(mountPoint: String, level: FreespaceLevel) async throws {
        let command = "/usr/sbin/diskutil secureErase freespace \(level.rawValue) \(shellQuoted(mountPoint))"
        let script = "do shell script \(appleScriptQuoted(command)) with administrator privileges"

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        do {
            try await withTaskCancellationHandler {
                while process.isRunning {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(250))
                }
            } onCancel: {
                if process.isRunning {
                    process.terminate()
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if process.terminationStatus != 0 {
            throw NSError(domain: "BeeGone", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: output?.isEmpty == false
                                     ? output!
                                     : "diskutil secureErase failed (exit \(process.terminationStatus))"])
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func appleScriptQuoted(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
