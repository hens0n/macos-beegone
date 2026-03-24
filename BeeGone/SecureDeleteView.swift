import SwiftUI
import UniformTypeIdentifiers

struct SecureDeleteView: View {
    @State private var files: [URL] = []
    @State private var erasePattern: ErasePattern = .dod3
    @State private var isDeleting = false
    @State private var showConfirmation = false
    @State private var progress = DeleteProgress()
    @State private var deleteTask: Task<Void, Never>?
    @State private var showApfsWarning = false
    @State private var toast: ToastMessage?
    @State private var isDragOver = false
    @State private var toastTask: Task<Void, Never>?
    @State private var apfsTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            // APFS warning
            if showApfsWarning {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("APFS uses copy-on-write. Overwriting may not erase original blocks. Use \"Wipe Free Space\" after deletion for stronger guarantees.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.96, green: 0.78, blue: 0.26))
                }
                .padding(12)
                .background(Color(red: 0.24, green: 0.18, blue: 0.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.42, green: 0.31, blue: 0.0), lineWidth: 1)
                )
                .cornerRadius(8)
            }

            // Drop zone
            dropZone

            // File list
            if !files.isEmpty {
                fileList
            }

            // Settings and delete button
            if !isDeleting {
                settingsBar
            }

            // Progress
            if isDeleting {
                progressPanel
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
        .confirmationDialog("Confirm Secure Deletion", isPresented: $showConfirmation) {
            Button("Delete \(files.count) file(s) forever", role: .destructive) {
                startDeletion()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will securely overwrite and permanently destroy \(files.count) file(s) using \(erasePattern.rawValue). This action is irreversible.")
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDragOver ? Color(red: 0.96, green: 0.65, blue: 0.14) : Color.white.opacity(0.15),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .background(
                    isDragOver ? Color(red: 0.96, green: 0.65, blue: 0.14).opacity(0.05) : Color.clear
                )
                .cornerRadius(8)

            VStack(spacing: 8) {
                Text("🐝")
                    .font(.system(size: 40))
                HStack(spacing: 4) {
                    Text("Drop files here or")
                        .foregroundColor(.secondary)
                    Button("browse") {
                        browseFiles()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.14))
                }
                .font(.system(size: 14))
            }
        }
        .frame(height: 120)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
            return true
        }
    }

    // MARK: - File List

    private var fileList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.lastPathComponent)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            Text(file.path)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            files.remove(at: index)
                            checkApfs()
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(4)
                }
            }
        }
        .frame(maxHeight: 200)
    }

    // MARK: - Settings

    private var settingsBar: some View {
        HStack {
            HStack(spacing: 8) {
                Text("Erase method:")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Picker("", selection: $erasePattern) {
                    ForEach(ErasePattern.allCases) { pattern in
                        Text(pattern.rawValue).tag(pattern)
                    }
                }
                .frame(width: 160)
            }
            Spacer()
            Button("Securely Delete") {
                showConfirmation = true
            }
            .buttonStyle(DangerButtonStyle())
            .disabled(files.isEmpty)
        }
    }

    // MARK: - Progress

    private var progressPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(progress.fileName) (\(progress.currentFile)/\(progress.totalFiles))")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("Pass \(progress.currentPass)/\(progress.totalPasses)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            ProgressView(value: progress.overallProgress)
                .tint(Color(red: 0.96, green: 0.65, blue: 0.14))

            HStack {
                Text("\(Int(progress.overallProgress * 100))%")
                    .font(.system(size: 13))
                Spacer()
                Button("Cancel") {
                    deleteTask?.cancel()
                }
                .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Actions

    private func browseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Select files to securely delete"

        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    addFiles([url])
                }
            }
        }
    }

    private func addFiles(_ urls: [URL]) {
        let newURLs = urls.filter { url in !files.contains(where: { $0.path == url.path }) }
        let validURLs = newURLs.filter { url in
            do {
                _ = try DeleteTargetValidator.inspect(path: url.path)
                return true
            } catch {
                showToast(error.localizedDescription, type: .error)
                return false
            }
        }
        files.append(contentsOf: validURLs)
        checkApfs()
    }

    private func checkApfs() {
        apfsTask?.cancel()
        let paths = files.map(\.path)
        apfsTask = Task {
            let volumes = VolumeManager.listVolumes()
            let hasApfs = paths.contains { path in
                VolumeManager.fileSystemType(for: path, volumes: volumes).contains("apfs")
            }
            await MainActor.run {
                showApfsWarning = hasApfs
            }
        }
    }

    private func startDeletion() {
        isDeleting = true
        let paths = files.map(\.path)
        let pattern = erasePattern

        deleteTask = Task {
            let deleter = SecureDeleter()
            do {
                let count = try await deleter.deleteFiles(
                    paths: paths,
                    pattern: pattern,
                    didDeletePath: { deletedPath in
                        Task { @MainActor in
                            files.removeAll(where: { $0.path == deletedPath })
                        }
                    },
                    progress: { p in
                        Task { @MainActor in
                            progress = p
                        }
                    }
                )
                await MainActor.run {
                    isDeleting = false
                    showApfsWarning = false
                    progress = DeleteProgress()
                    showToast("\(count) file(s) securely deleted.", type: .success)
                }
            } catch DeleteBatchError.failed(let deletedPaths, let underlying) {
                await MainActor.run {
                    isDeleting = false
                    files.removeAll(where: { deletedPaths.contains($0.path) })
                    progress = DeleteProgress()
                    checkApfs()
                    showToast(underlying.localizedDescription, type: .error)
                }
            } catch is CancellationError {
                await MainActor.run {
                    isDeleting = false
                    progress = DeleteProgress()
                    checkApfs()
                    showToast("Operation cancelled.", type: .error)
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    progress = DeleteProgress()
                    checkApfs()
                    showToast(error.localizedDescription, type: .error)
                }
            }
        }
    }

    // MARK: - Toast

    private func showToast(_ message: String, type: ToastType) {
        toastTask?.cancel()
        toast = ToastMessage(message: message, type: type)
        toastTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
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

enum ToastType { case success, error }
struct ToastMessage { let message: String; let type: ToastType }

// MARK: - Button Styles

struct DangerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(isEnabled ? Color(red: 0.9, green: 0.27, blue: 0.27) : Color.gray.opacity(0.3))
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundColor(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
