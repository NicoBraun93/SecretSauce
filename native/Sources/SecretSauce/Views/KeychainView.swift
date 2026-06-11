import SwiftUI

struct KeychainView: View {
    @State private var keys: [String] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Secrets are stored in the macOS Keychain under service `SecretSauce:<key>`.")
                    .font(.callout)
                    .foregroundStyle(Color.dsMutedForeground)
                Spacer()
            }
            .padding(12)
            Divider()
            VarTableView(
                vars: keys.map { EnvVar(key: $0, value: "") },
                onUpsert: { key, value in
                    do {
                        try await Task.detached(priority: .userInitiated) {
                            try KeychainService.set(key: key, value: value)
                        }.value
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    load()
                },
                onDelete: { key in
                    await Task.detached(priority: .userInitiated) {
                        KeychainService.delete(key: key)
                    }.value
                    load()
                },
                secret: true,
                onReveal: { key in
                    await Task.detached(priority: .userInitiated) {
                        KeychainService.get(key: key)
                    }.value
                }
            )
        }
        .errorAlert($errorMessage)
        .onAppear(perform: load)
    }

    private func load() {
        keys = KeychainService.list()
    }
}
