import Foundation

struct VolumeInfo: Identifiable, Sendable {
    var id: String { identifier }
    let name: String
    let mountPoint: String
    let identifier: String
    let fileSystem: String
    let totalSize: UInt64
    let freeSpace: UInt64
    let isInternal: Bool
    let isRemovable: Bool
}

enum VolumeManager {
    static func listVolumes() -> [VolumeInfo] {
        let identifiers = getVolumeIdentifiers()
        var volumes: [VolumeInfo] = []
        var seen = Set<String>()

        for id in identifiers {
            if let vol = getVolumeDetails(identifier: id), !seen.contains(vol.mountPoint) {
                seen.insert(vol.mountPoint)
                volumes.append(vol)
            }
        }
        return volumes
    }

    static func fileSystemType(for path: String) -> String {
        let volumes = listVolumes()
        // Find the volume with the longest matching mount point prefix
        let match = volumes
            .filter { path.hasPrefix($0.mountPoint) }
            .max(by: { $0.mountPoint.count < $1.mountPoint.count })
        return match?.fileSystem ?? "unknown"
    }

    private static func getVolumeIdentifiers() -> [String] {
        guard let plistXml = runCommand("/usr/sbin/diskutil", args: ["list", "-plist"]),
              let plist = parsePlist(plistXml) as? [String: Any],
              let disks = plist["AllDisksAndPartitions"] as? [[String: Any]] else {
            return []
        }

        var identifiers: [String] = []
        for disk in disks {
            if let partitions = disk["Partitions"] as? [[String: Any]] {
                for p in partitions {
                    if let id = p["DeviceIdentifier"] as? String { identifiers.append(id) }
                }
            }
            if let apfsVolumes = disk["APFSVolumes"] as? [[String: Any]] {
                for v in apfsVolumes {
                    if let id = v["DeviceIdentifier"] as? String { identifiers.append(id) }
                }
            }
        }
        return identifiers
    }

    private static func getVolumeDetails(identifier: String) -> VolumeInfo? {
        guard let plistXml = runCommand("/usr/sbin/diskutil", args: ["info", "-plist", identifier]),
              let info = parsePlist(plistXml) as? [String: Any],
              let mountPoint = info["MountPoint"] as? String,
              !mountPoint.isEmpty else {
            return nil
        }

        // Skip system volumes
        let skipPrefixes = [
            "/System/Volumes/Preboot",
            "/System/Volumes/Recovery",
            "/System/Volumes/VM",
            "/System/Volumes/Update",
            "/System/Volumes/Data/com.apple.TimeMachine"
        ]
        if skipPrefixes.contains(where: { mountPoint.hasPrefix($0) }) { return nil }

        let fsType = (info["FilesystemType"] as? String ?? info["FilesystemName"] as? String ?? "unknown").lowercased()
        let freeSpace = (info["APFSContainerFree"] as? UInt64) ?? (info["FreeSpace"] as? UInt64) ?? 0

        return VolumeInfo(
            name: info["VolumeName"] as? String ?? identifier,
            mountPoint: mountPoint,
            identifier: info["DeviceIdentifier"] as? String ?? identifier,
            fileSystem: fsType,
            totalSize: info["TotalSize"] as? UInt64 ?? 0,
            freeSpace: freeSpace,
            isInternal: info["Internal"] as? Bool ?? false,
            isRemovable: info["Removable"] as? Bool ?? info["RemovableMedia"] as? Bool ?? false
        )
    }

    private static func runCommand(_ path: String, args: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func parsePlist(_ xml: String) -> Any? {
        // Use plutil to convert plist XML to JSON, then parse
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        process.arguments = ["-convert", "json", "-o", "-", "-"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            inputPipe.fileHandleForWriting.write(xml.data(using: .utf8)!)
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }
}
