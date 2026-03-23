import Foundation

enum ErasePattern: String, CaseIterable, Identifiable {
    case random1 = "1-pass random"
    case dod3 = "3-pass DoD"
    case random7 = "7-pass random"
    case gutmann35 = "35-pass Gutmann"
    case zero1 = "1-pass zero"

    var id: String { rawValue }

    var totalPasses: Int {
        switch self {
        case .random1: 1
        case .dod3: 3
        case .random7: 7
        case .gutmann35: 35
        case .zero1: 1
        }
    }
}

struct DeleteProgress: Sendable {
    var currentFile: Int = 0
    var totalFiles: Int = 0
    var fileName: String = ""
    var currentPass: Int = 0
    var totalPasses: Int = 0
    var bytesWritten: UInt64 = 0
    var totalBytes: UInt64 = 0
    var overallProgress: Double = 0
}

actor SecureDeleter {
    private let chunkSize = 1024 * 1024 // 1 MB

    func deleteFiles(
        paths: [String],
        pattern: ErasePattern,
        progress: @Sendable (DeleteProgress) -> Void
    ) async throws -> Int {
        var deleted = 0
        let totalFiles = paths.count

        for (index, path) in paths.enumerated() {
            try Task.checkCancellation()
            try await deleteFile(
                path: path,
                pattern: pattern,
                fileIndex: index,
                totalFiles: totalFiles,
                progress: progress
            )
            deleted += 1
        }
        return deleted
    }

    private func deleteFile(
        path: String,
        pattern: ErasePattern,
        fileIndex: Int,
        totalFiles: Int,
        progress: @Sendable (DeleteProgress) -> Void
    ) async throws {
        let fileManager = FileManager.default
        let attrs = try fileManager.attributesOfItem(atPath: path)
        let fileSize = (attrs[.size] as? UInt64) ?? 0
        let totalPasses = pattern.totalPasses
        let fileName = (path as NSString).lastPathComponent

        // Open file for writing
        let fd = open(path, O_WRONLY)
        guard fd >= 0 else {
            throw NSError(domain: "BeeGone", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot open file: \(path)"])
        }
        defer {
            // We close after overwrite, before rename+unlink
        }

        do {
            for pass in 1...totalPasses {
                try Task.checkCancellation()

                // Seek to beginning
                lseek(fd, 0, SEEK_SET)

                var bytesWritten: UInt64 = 0
                while bytesWritten < fileSize {
                    try Task.checkCancellation()

                    let remaining = fileSize - bytesWritten
                    let writeSize = min(UInt64(chunkSize), remaining)
                    let buffer = generatePassData(pattern: pattern, pass: pass, size: Int(writeSize))

                    let result = buffer.withUnsafeBytes { ptr -> Int in
                        write(fd, ptr.baseAddress!, Int(writeSize))
                    }
                    guard result > 0 else {
                        throw NSError(domain: "BeeGone", code: 2,
                                      userInfo: [NSLocalizedDescriptionKey: "Write failed at offset \(bytesWritten)"])
                    }

                    bytesWritten += UInt64(result)

                    let fileProgress = Double(pass - 1) / Double(totalPasses) +
                        Double(bytesWritten) / Double(fileSize) / Double(totalPasses)
                    let overall = (Double(fileIndex) + fileProgress) / Double(totalFiles)

                    progress(DeleteProgress(
                        currentFile: fileIndex + 1,
                        totalFiles: totalFiles,
                        fileName: fileName,
                        currentPass: pass,
                        totalPasses: totalPasses,
                        bytesWritten: bytesWritten,
                        totalBytes: fileSize,
                        overallProgress: overall
                    ))
                }

                // F_FULLFSYNC forces physical disk write (stronger than fsync on macOS)
                _ = fcntl(fd, F_FULLFSYNC)
            }
        } catch {
            close(fd)
            throw error
        }

        close(fd)

        // Rename to random name to obscure filename from filesystem journal
        let dir = (path as NSString).deletingLastPathComponent
        let randomName = (dir as NSString).appendingPathComponent(UUID().uuidString)
        try fileManager.moveItem(atPath: path, toPath: randomName)

        // Delete
        try fileManager.removeItem(atPath: randomName)
    }

    private func generatePassData(pattern: ErasePattern, pass: Int, size: Int) -> Data {
        switch pattern {
        case .zero1:
            return Data(count: size)
        case .random1, .random7, .gutmann35:
            return randomData(size: size)
        case .dod3:
            switch pass {
            case 1: return Data(count: size) // zeros
            case 2: return Data(repeating: 0xFF, count: size)
            default: return randomData(size: size)
            }
        }
    }

    private func randomData(size: Int) -> Data {
        var data = Data(count: size)
        data.withUnsafeMutableBytes { ptr in
            guard let addr = ptr.baseAddress else { return }
            // SecRandomCopyBytes is cryptographically secure
            _ = SecRandomCopyBytes(kSecRandomDefault, size, addr)
        }
        return data
    }
}
