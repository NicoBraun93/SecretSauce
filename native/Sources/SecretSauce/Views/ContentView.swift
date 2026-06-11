import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case localEnv = "Local Env"
    case shell = "Shell Profile"
    case envFiles = ".env Files"
    case keychain = "Keychain Secrets"
    case launchd = "Launchd Services"
    case network = "Network Monitor"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .localEnv: return "macwindow"
        case .shell: return "terminal"
        case .envFiles: return "doc.text"
        case .keychain: return "key.fill"
        case .launchd: return "gearshape.2"
        case .network: return "network"
        }
    }
}

struct ContentView: View {
    @State private var section: AppSection = .localEnv

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: Binding(
                get: { Optional(section) },
                set: { if let s = $0 { section = s } }
            )) { s in
                Label(s.rawValue, systemImage: s.icon)
                    .tag(s)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .listStyle(.sidebar)
        } detail: {
            switch section {
            case .localEnv: LocalEnvView()
            case .shell: ShellProfileView()
            case .envFiles: EnvFilesView()
            case .keychain: KeychainView()
            case .launchd: LaunchdView()
            case .network: NetworkView()
            }
        }
        .navigationTitle("SecretSauce")
    }
}
