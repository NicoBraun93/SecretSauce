import SwiftUI

struct ShellProfileView: View {
    @State private var path = ""
    @State private var vars: [EnvVar] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Editing").foregroundStyle(Color.dsMutedForeground)
                PathPill(text: path.isEmpty ? "…" : path)
                Spacer()
                Text("Restart your terminal or run `source \(URL(fileURLWithPath: path).lastPathComponent)` to apply.")
                    .font(.callout)
                    .foregroundStyle(Color.dsMutedForeground)
            }
            .padding(12)
            Divider()
            VarTableView(
                vars: vars,
                onUpsert: { key, value in
                    await runOffMain { try ShellProfileService.upsert(key: key, value: value) }
                    load()
                },
                onDelete: { key in
                    await runOffMain { try ShellProfileService.delete(key: key) }
                    load()
                }
            )
        }
        .errorAlert($errorMessage)
        .onAppear(perform: load)
    }

    private func load() {
        let r = ShellProfileService.read()
        path = r.path
        vars = r.vars
    }

    private func runOffMain(_ work: @escaping () throws -> Void) async {
        do {
            try await Task.detached(priority: .userInitiated) { try work() }.value
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PathPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.callout, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.dsSecondary, in: Capsule())
    }
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Error",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
