import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EnvFilesView: View {
    @State private var filePath: String?
    @State private var vars: [EnvVar] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Open .env file…") { open() }
                Button("New .env file…") { create() }
                if let filePath {
                    Text("File").foregroundStyle(.secondary)
                    PathPill(text: filePath)
                }
                Spacer()
            }
            .padding(12)
            Divider()
            if filePath == nil {
                Spacer()
                Text("Open or create a .env file to manage its variables.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                VarTableView(
                    vars: vars,
                    onUpsert: { key, value in
                        var next = vars
                        if let idx = next.firstIndex(where: { $0.key == key }) {
                            next[idx].value = value
                        } else {
                            next.append(EnvVar(key: key, value: value))
                        }
                        persist(next)
                    },
                    onDelete: { key in
                        persist(vars.filter { $0.key != key })
                    }
                )
            }
        }
        .errorAlert($errorMessage)
    }

    private func open() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        filePath = url.path
        vars = EnvFileService.read(filePath: url.path)
    }

    private func create() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ".env"
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
            filePath = url.path
            vars = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persist(_ next: [EnvVar]) {
        guard let filePath else { return }
        do {
            try EnvFileService.write(filePath: filePath, vars: next)
            vars = next
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
