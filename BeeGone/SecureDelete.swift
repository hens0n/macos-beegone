import Foundation
import Security

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

struct DeleteTargetInfo: Sendable {
    let path: String
    let fileName: String
    let fileSize: UInt64
}

enum DeleteTargetValidationError: LocalizedError {
    case notFound(String)
    case symlink(String)
    case notRegularFile(String)
    case multiplyLinked(String)
    case inaccessible(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path):
            "File no longer exists: \(path)"
        case .symlink(let path):
            "Refusing to securely delete symlink: \(path)"
        case .notRegularFile(let path):
            "Only regular files can be securely deleted: \(path)"
        case .multiplyLinked(let path):
            "Refusing to securely delete hard-linked file: \(path)"
        case .inaccessible(let path):
            "Cannot inspect file: \(path)"
        }
    }
}

enum DeleteBatchError: LocalizedError {
    case failed(deletedPaths: [String], underlying: Error)

    var errorDescription: String? {
        switch self {
        case .failed(_, let underlying):
            underlying.localizedDescription
        }
    }
}

enum DeleteTargetValidator {
    static func inspect(path: String) throws -> DeleteTargetInfo {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            if errno == ENOENT {
                throw DeleteTargetValidationError.notFound(path)
            }
            throw DeleteTargetValidationError.inaccessible(path)
        }

        guard (info.st_mode & S_IFMT) != S_IFLNK else {
            throw DeleteTargetValidationError.symlink(path)
        }

        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw DeleteTargetValidationError.notRegularFile(path)
        }

        guard info.st_nlink <= 1 else {
            throw DeleteTargetValidationError.multiplyLinked(path)
        }

        return DeleteTargetInfo(
            path: path,
            fileName: (path as NSString).lastPathComponent,
            fileSize: UInt64(info.st_size)
        )
    }
}

actor SecureDeleter {
    private let chunkSize = 1024 * 1024 // 1 MB
    private let progressInterval = UInt64(8 * 1024 * 1024)

    func deleteFiles(
        paths: [String],
        pattern: ErasePattern,
        didDeletePath: @Sendable (String) -> Void,
        progress: @Sendable (DeleteProgress) -> Void
    ) async throws -> Int {
        var deleted = 0
        var deletedPaths: [String] = []
        let totalFiles = paths.count

        do {
            for (index, path) in paths.enumerated() {
                try Task.checkCancellation()
                try await deleteFile(
                    path: path,
                    pattern: pattern,
                    fileIndex: index,
                    totalFiles: totalFiles,
                    progress: progress
                )
                deletedPaths.append(path)
                didDeletePath(path)
                deleted += 1
            }
        } catch {
            throw DeleteBatchError.failed(deletedPaths: deletedPaths, underlying: error)
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
        let target = try DeleteTargetValidator.inspect(path: path)
        let fileSize = target.fileSize
        let totalPasses = pattern.totalPasses
        let fileName = target.fileName

        let fd = open(path, O_WRONLY | O_NOFOLLOW)
        guard fd >= 0 else {
            throw NSError(domain: "BeeGone", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot open file: \(path)"])
        }
        do {
            if fileSize == 0 {
                progress(DeleteProgress(
                    currentFile: fileIndex + 1,
                    totalFiles: totalFiles,
                    fileName: fileName,
                    currentPass: totalPasses,
                    totalPasses: totalPasses,
                    bytesWritten: 0,
                    totalBytes: 0,
                    overallProgress: Double(fileIndex + 1) / Double(totalFiles)
                ))
            }

            for pass in 1...totalPasses {
                try Task.checkCancellation()

                lseek(fd, 0, SEEK_SET)

                var bytesWritten: UInt64 = 0
                var lastReportedBytes: UInt64 = 0
                while bytesWritten < fileSize {
                    try Task.checkCancellation()

                    let remaining = fileSize - bytesWritten
                    let writeSize = min(UInt64(chunkSize), remaining)
                    let buffer = try generatePassData(pattern: pattern, pass: pass, size: Int(writeSize))

                    let result = buffer.withUnsafeBytes { ptr -> Int in
                        write(fd, ptr.baseAddress!, Int(writeSize))
                    }
                    guard result > 0 else {
                        throw NSError(domain: "BeeGone", code: 2,
                                      userInfo: [NSLocalizedDescriptionKey: "Write failed at offset \(bytesWritten)"])
                    }

                    bytesWritten += UInt64(result)

                    let shouldReport = bytesWritten == fileSize ||
                        bytesWritten - lastReportedBytes >= progressInterval

                    if shouldReport {
                        lastReportedBytes = bytesWritten

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
                }

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

    private func generatePassData(pattern: ErasePattern, pass: Int, size: Int) throws -> Data {
        switch pattern {
        case .zero1:
            return Data(count: size)
        case .random1, .random7, .gutmann35:
            return try randomData(size: size)
        case .dod3:
            switch pass {
            case 1: return Data(count: size) // zeros
            case 2: return Data(repeating: 0xFF, count: size)
            default: return try randomData(size: size)
            }
        }
    }

    private func randomData(size: Int) throws -> Data {
        var data = Data(count: size)
        let status = data.withUnsafeMutableBytes { ptr in
            guard let addr = ptr.baseAddress else { return OSStatus(errSecParam) }
            return SecRandomCopyBytes(kSecRandomDefault, size, addr)
        }
        guard status == errSecSuccess else {
            throw NSError(
                domain: "BeeGone",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Secure random generation failed."]
            )
        }
        return data
    }
}
