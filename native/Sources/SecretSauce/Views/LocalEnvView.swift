import SwiftUI

struct LocalEnvView: View {
    @State private var vars: [EnvVar] = []
    @State private var shellVars: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Viewing active session environment variables. Save any variable to make it persistent in your Shell Profile.")
                    .font(.callout)
                    .foregroundStyle(Color.dsMutedForeground)
                Spacer()
                Button("Refresh") { load() }
            }
            .padding(12)
            Divider()
            VarTableView(
                vars: vars,
                onUpsert: { key, value in
                    do {
                        try ShellProfileService.upsert(key: key, value: value)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    load()
                },
                onDelete: { key in
                    do {
                        try ShellProfileService.delete(key: key)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    load()
                },
                isSystemEnv: true,
                shellVars: shellVars
            )
        }
        .errorAlert($errorMessage)
        .onAppear(perform: load)
    }

    private func load() {
        vars = ProcessInfo.processInfo.environment
            .map { EnvVar(key: $0.key, value: $0.value) }
            .sorted { $0.key.localizedCompare($1.key) == .orderedAscending }
        shellVars = Set(ShellProfileService.read().vars.map(\.key))
    }
}
