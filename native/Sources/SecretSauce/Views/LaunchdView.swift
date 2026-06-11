import SwiftUI

struct LaunchdView: View {
    @State private var services: [LaunchdService] = []
    @State private var selectedLabel: String?
    @State private var loading = true
    @State private var errorMessage: String?

    private var selected: LaunchdService? {
        services.first { $0.label == selectedLabel }
    }

    var body: some View {
        // A plain HStack instead of HSplitView: HSplitView is AppKit-backed and
        // sizes itself to the full window width inside a NavigationSplitView
        // detail column, pushing content past the window's right edge.
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
            Divider()
            details
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .errorAlert($errorMessage)
        .onAppear { load() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Launch Agents").font(.headline)
                Spacer()
                Button("Refresh") { load() }
                    .controlSize(.small)
            }
            .padding(10)
            Divider()
            if loading && services.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if services.isEmpty {
                Spacer()
                Text("No launch agents found in ~/Library/LaunchAgents.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                List(services, selection: $selectedLabel) { s in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(s.loaded && s.pid != nil ? Color.green : s.loaded ? Color.yellow : Color.gray)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.label)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(URL(fileURLWithPath: s.filePath).lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .tag(s.label)
                }
                .listStyle(.sidebar)
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        if let s = selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.label).font(.title2.weight(.semibold))
                        PathPill(text: s.filePath)
                    }

                    if !s.program.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("EXEC COMMAND")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(s.program)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    HStack(spacing: 12) {
                        statusCard("State", s.loaded ? "Loaded" : "Unloaded", s.loaded ? .green : .secondary)
                        statusCard("Process (PID)", s.pid.map(String.init) ?? "Not Running", s.pid != nil ? .green : .secondary)
                        if s.loaded, let code = s.lastExitCode {
                            statusCard("Last Exit Code", String(code), .primary)
                        }
                    }

                    HStack(spacing: 8) {
                        if !s.loaded {
                            Button("Load Agent Plist") { control(.load, s) }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Unload Agent Plist", role: .destructive) { control(.unload, s) }
                            if s.pid != nil {
                                Button("Stop Service") { control(.stop, s) }
                            } else {
                                Button("Start Service") { control(.start, s) }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Environment Variables").font(.headline)
                        Text("Defined under the `EnvironmentVariables` key.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        VarTableView(
                            vars: s.vars,
                            onUpsert: { key, value in
                                do {
                                    try LaunchdManager.upsertVar(filePath: s.filePath, key: key, value: value)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                                load()
                            },
                            onDelete: { key in
                                do {
                                    try LaunchdManager.deleteVar(filePath: s.filePath, key: key)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                                load()
                            }
                        )
                        .frame(minHeight: 280)
                    }
                }
                .padding(16)
            }
        } else {
            VStack {
                Spacer()
                Text("Select a launch agent from the list to view and manage its configuration.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func statusCard(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.medium))
                .foregroundStyle(color)
        }
        .padding(10)
        .frame(minWidth: 130, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func control(_ action: LaunchdManager.Action, _ s: LaunchdService) {
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try LaunchdManager.control(action: action, filePath: s.filePath, label: s.label)
                }.value
            } catch {
                errorMessage = "launchctl \(action.rawValue) failed: \(error.localizedDescription)"
            }
            // Give launchd a moment to settle before refreshing status.
            try? await Task.sleep(nanoseconds: 500_000_000)
            load()
        }
    }

    private func load() {
        loading = true
        Task {
            let list = await Task.detached(priority: .userInitiated) { LaunchdManager.list() }.value
            services = list
            if selectedLabel == nil { selectedLabel = list.first?.label }
            loading = false
        }
    }
}
