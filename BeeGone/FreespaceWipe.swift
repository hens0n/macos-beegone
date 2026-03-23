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
    /// Wipes free space on a volume using diskutil secureErase freespace.
    /// Requires admin privileges — prompts via osascript.
    static func wipe(
        mountPoint: String,
        level: FreespaceLevel,
        progress: @Sendable (Double) -> Void
    ) async throws {
        let command = "/usr/sbin/diskutil secureErase freespace \(level.rawValue) \\\"\(mountPoint)\\\""

        // Use osascript to run with admin privileges (triggers native macOS auth dialog)
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(command)\" with administrator privileges"]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        // Read output for progress updates
        let handle = pipe.fileHandleForReading
        var buffer = ""

        while process.isRunning {
            try Task.checkCancellation()

            let data = handle.availableData
            if data.isEmpty {
                try await Task.sleep(for: .milliseconds(500))
                continue
            }

            buffer += String(data: data, encoding: .utf8) ?? ""

            // diskutil outputs progress like "X% complete"
            if let range = buffer.range(of: #"(\d+(?:\.\d+)?)%"#, options: .regularExpression) {
                let match = String(buffer[range]).dropLast() // remove %
                if let pct = Double(match) {
                    progress(pct / 100.0)
                }
            }
        }

        if process.terminationStatus != 0 {
            throw NSError(domain: "BeeGone", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "diskutil secureErase failed (exit \(process.terminationStatus))"])
        }
    }
}
