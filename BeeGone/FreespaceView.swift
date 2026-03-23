import SwiftUI

struct FreespaceView: View {
    @State private var volumes: [VolumeInfo] = []
    @State private var isLoading = true
    @State private var isWiping = false
    @State private var wipeProgress: Double = 0
    @State private var wipeTask: Task<Void, Never>?
    @State private var wipeLevels: [String: FreespaceLevel] = [:]
    @State private var toast: ToastMessage?

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Mounted Volumes")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Refresh") {
                    loadVolumes()
                }
                .buttonStyle(GhostButtonStyle())
            }

            // Volume list
            if isLoading {
                Spacer()
                ProgressView("Scanning volumes...")
                    .foregroundColor(.secondary)
                Spacer()
            } else if volumes.isEmpty {
                Spacer()
                Text("No mounted volumes found.")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(volumes) { vol in
                            volumeCard(vol)
                        }
                    }
                }
            }

            // Wipe progress
            if isWiping {
                VStack(spacing: 8) {
                    Text("Wiping free space...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    ProgressView(value: wipeProgress)
                        .tint(Color(red: 0.96, green: 0.65, blue: 0.14))

                    HStack {
                        Text("\(Int(wipeProgress * 100))%")
                            .font(.system(size: 13))
                        Spacer()
                        Button("Cancel") {
                            wipeTask?.cancel()
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }

            Spacer()
        }
        .padding(20)
        .overlay(alignment: .bottomTrailing) {
            if let toast {
                toastView(toast)
                    .padding(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast != nil)
        .onAppear { loadVolumes() }
    }

    private func volumeCard(_ vol: VolumeInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(vol.name)
                        .font(.system(size: 14, weight: .semibold))

                    Text(vol.isRemovable ? "External" : "Internal")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(vol.isRemovable
                                    ? Color(red: 0.23, green: 0.17, blue: 0.17)
                                    : Color(red: 0.17, green: 0.23, blue: 0.17))
                        .foregroundColor(vol.isRemovable
                                         ? Color(red: 0.81, green: 0.56, blue: 0.44)
                                         : Color(red: 0.44, green: 0.81, blue: 0.44))
                        .cornerRadius(10)
                }

                HStack(spacing: 12) {
                    Text(vol.mountPoint)
                    Text(vol.fileSystem.uppercased())
                    Text("\(formatSize(vol.freeSpace)) free of \(formatSize(vol.totalSize))")
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Picker("", selection: binding(for: vol.identifier)) {
                    ForEach(FreespaceLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .frame(width: 170)

                Button("Wipe") {
                    startWipe(vol)
                }
                .buttonStyle(WipeButtonStyle())
                .disabled(isWiping)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    private func binding(for identifier: String) -> Binding<FreespaceLevel> {
        Binding(
            get: { wipeLevels[identifier] ?? .dod },
            set: { wipeLevels[identifier] = $0 }
        )
    }

    private func loadVolumes() {
        isLoading = true
        Task {
            let vols = VolumeManager.listVolumes()
            await MainActor.run {
                volumes = vols
                isLoading = false
            }
        }
    }

    private func startWipe(_ vol: VolumeInfo) {
        let level = wipeLevels[vol.identifier] ?? .dod
        isWiping = true
        wipeProgress = 0

        wipeTask = Task {
            do {
                try await FreespaceWiper.wipe(mountPoint: vol.mountPoint, level: level) { pct in
                    Task { @MainActor in
                        wipeProgress = pct
                    }
                }
                await MainActor.run {
                    isWiping = false
                    wipeProgress = 0
                    showToast("Free space wiped successfully.", type: .success)
                    loadVolumes()
                }
            } catch is CancellationError {
                await MainActor.run {
                    isWiping = false
                    wipeProgress = 0
                    showToast("Wipe cancelled.", type: .error)
                }
            } catch {
                await MainActor.run {
                    isWiping = false
                    wipeProgress = 0
                    showToast(error.localizedDescription, type: .error)
                }
            }
        }
    }

    private func showToast(_ message: String, type: ToastType) {
        toast = ToastMessage(message: message, type: type)
        Task {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run { toast = nil }
        }
    }

    private func toastView(_ msg: ToastMessage) -> some View {
        Text(msg.message)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(msg.type == .success
                        ? Color(red: 0.1, green: 0.23, blue: 0.1)
                        : Color(red: 0.23, green: 0.1, blue: 0.1))
            .foregroundColor(msg.type == .success
                             ? Color(red: 0.44, green: 0.81, blue: 0.44)
                             : Color(red: 0.81, green: 0.44, blue: 0.44))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(msg.type == .success
                            ? Color(red: 0.17, green: 0.35, blue: 0.17)
                            : Color(red: 0.35, green: 0.17, blue: 0.17), lineWidth: 1)
            )
            .cornerRadius(8)
    }
}

struct WipeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(isEnabled ? Color(red: 0.96, green: 0.65, blue: 0.14) : Color.gray.opacity(0.3))
            .cornerRadius(4)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private func formatSize(_ bytes: UInt64) -> String {
    let kb = Double(bytes) / 1024
    let mb = kb / 1024
    let gb = mb / 1024
    if gb >= 1 { return String(format: "%.1f GB", gb) }
    if mb >= 1 { return String(format: "%.1f MB", mb) }
    if kb >= 1 { return String(format: "%.1f KB", kb) }
    return "\(bytes) B"
}
