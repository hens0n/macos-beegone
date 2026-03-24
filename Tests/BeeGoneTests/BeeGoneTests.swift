import XCTest
@testable import BeeGone

final class BeeGoneTests: XCTestCase {
    func testBestVolumeMatchRespectsPathBoundaries() {
        let volumes = [
            VolumeInfo(name: "Data", mountPoint: "/Volumes/Data", identifier: "disk1s1", fileSystem: "apfs", totalSize: 1, freeSpace: 1, isInternal: false, isRemovable: true),
            VolumeInfo(name: "Data-2", mountPoint: "/Volumes/Data-2", identifier: "disk1s2", fileSystem: "hfs", totalSize: 1, freeSpace: 1, isInternal: false, isRemovable: true)
        ]

        let match = VolumeManager.bestVolumeMatch(for: "/Volumes/Data-2/file.txt", in: volumes)

        XCTAssertEqual(match?.identifier, "disk1s2")
    }

    func testDeleteTargetValidatorRejectsSymlinks() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("real.txt")
        let symlinkURL = dir.appendingPathComponent("link.txt")
        try Data("hello".utf8).write(to: fileURL)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: fileURL)

        XCTAssertThrowsError(try DeleteTargetValidator.inspect(path: symlinkURL.path)) { error in
            XCTAssertTrue(error.localizedDescription.contains("symlink"))
        }
    }

    func testDeleteTargetValidatorRejectsHardLinkedFiles() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = dir.appendingPathComponent("a.txt")
        let second = dir.appendingPathComponent("b.txt")
        try Data("hello".utf8).write(to: first)
        try FileManager.default.linkItem(at: first, to: second)

        XCTAssertThrowsError(try DeleteTargetValidator.inspect(path: first.path)) { error in
            XCTAssertTrue(error.localizedDescription.contains("hard-linked"))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
