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
                    .help("Re-reads ~/Library/LaunchAgents, `launchctl list`, the disabled overrides and the process table.")
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
                            .fill(dotColor(s))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.label)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(usageCaption(s) ?? URL(fileURLWithPath: s.filePath).lastPathComponent)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 4)
                        if s.disabled {
                            Image(systemName: "moon.zzz.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .help(stateSummary(s))
                    .tag(s.label)
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func dotColor(_ s: LaunchdService) -> Color {
        if s.disabled { return Color.dsMutedForeground }
        if s.loaded && s.pid != nil { return Color.dsSuccess }
        return s.loaded ? Color.dsWarning : Color.dsMutedForeground
    }

    /// "14 MB · 2.3%" for running jobs, nil when there is no process to measure.
    private func usageCaption(_ s: LaunchdService) -> String? {
        guard let mem = s.memoryBytes else { return nil }
        var caption = ByteFormat.string(mem)
        if let cpu = s.cpuPercent {
            caption += String(format: " · %.1f%%", cpu)
        }
        return caption
    }

    private func stateSummary(_ s: LaunchdService) -> String {
        if s.disabled {
            return "Disabled in launchd's override database — stays off after a reboot."
        }
        if !s.loaded {
            return "Not loaded in this session, but the plist is still in ~/Library/LaunchAgents, so it loads again at the next login."
        }
        if s.pid == nil {
            return "Loaded but not running — waiting for its trigger, or it has already exited."
        }
        return "Loaded and running (pid \(s.pid ?? 0))."
    }

    @ViewBuilder
    private var details: some View {
        if let s = selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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
                                .background(Color.dsSecondary, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    controlRow(s)
                    statusGrid(s)

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

    // MARK: - Controls

    /// The whole tab boils down to two questions: does it come back after a
    /// reboot (the toggle), and is it running right now (the button). Everything
    /// else is explanation, and explanation lives in the ⓘ tooltip so the row
    /// stays readable at a glance.
    private func controlRow(_ s: LaunchdService) -> some View {
        HStack(spacing: 8) {
            Toggle("Autostart", isOn: autostartBinding(s))
                .toggleStyle(.switch)

            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .help(controlsExplanation(s))

            Spacer()

            Button(s.pid != nil ? "Deactivate" : "Activate") {
                s.pid != nil ? deactivate(s) : activate(s)
            }
            .buttonStyle(.bordered)
            .tint(s.pid != nil ? .red : Color.dsPrimary)
        }
        .padding(12)
        .background(Color.dsSecondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func controlsExplanation(_ s: LaunchdService) -> String {
        var text = """
        Autostart — permanent. launchd re-reads ~/Library/LaunchAgents at every login, so simply stopping an agent does not keep it away. Switching this off runs `launchctl disable`, which records the label in launchd's override database and survives a reboot. Switching it on runs `launchctl enable` and loads the plist again.

        Activate / Deactivate — right now, until the next login. Deactivate unloads the agent and kills its process; Activate loads it and starts it.
        """
        if !s.runAtLoad {
            text += "\n\nThis agent has no `RunAtLoad` key, so even with Autostart on launchd only loads it at login and waits for its trigger (a socket, a watched path, or a calendar interval) before running it."
        }
        if s.keepAlive {
            text += "\n\n`KeepAlive` is set: launchd restarts this job whenever it exits, so Deactivate (which unloads it) is the only thing that stops it for this session."
        }
        return text
    }

    // MARK: - Status

    /// A grid rather than an HStack: eight fixed-width cards overflow the detail
    /// column on a narrow window.
    private func statusGrid(_ s: LaunchdService) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            statusCard("State", s.loaded ? "Loaded" : "Unloaded",
                       s.loaded ? Color.dsSuccess : Color.dsMutedForeground,
                       help: "Whether the job is registered with the launchd session running right now. Says nothing about the next login — that is the Autostart toggle.")

            statusCard("Starts", startsValue(s), startsColor(s),
                       help: startsHelp(s))

            statusCard("Process (PID)", s.pid.map(String.init) ?? "Not Running",
                       s.pid != nil ? Color.dsSuccess : Color.dsMutedForeground,
                       help: "The pid launchd tracks for this job. A job can be loaded without running — on-demand agents only start when their trigger fires.")

            statusCard("Memory (RSS)", s.memoryBytes.map(ByteFormat.string) ?? "—",
                       s.memoryBytes != nil ? Color.dsPrimary : Color.dsMutedForeground,
                       help: "Resident set size: physical RAM held by the job and its \(s.childProcessCount) child process\(s.childProcessCount == 1 ? "" : "es"). Excludes swapped-out and file-backed pages, so it is what the job actually costs in RAM right now.")

            statusCard("CPU", s.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—",
                       cpuColor(s),
                       help: "CPU share of the job's process tree as reported by `ps` — a decaying average over roughly the last minute, not an instant sample. 100% is one saturated core, so a multi-threaded job can go above it.")

            statusCard("Processes", s.pid != nil ? "\(s.childProcessCount + 1)" : "—",
                       s.pid != nil ? Color.dsPrimary : Color.dsMutedForeground,
                       help: "Main process plus every descendant it spawned. Memory and CPU above are summed over all of them, because wrapper scripts put the real cost in their children.")

            statusCard("Uptime", s.uptime ?? "—",
                       s.uptime != nil ? Color.dsPrimary : Color.dsMutedForeground,
                       help: "Wall-clock time since the main process started, as `[days-]hh:mm:ss`. A value that keeps resetting means the job is crash-looping and being restarted by KeepAlive.")

            if s.loaded, let code = s.lastExitCode {
                statusCard("Last Exit Code", String(code),
                           code == 0 ? Color.dsPrimary : Color.dsWarning,
                           help: "Exit status of the last run, from `launchctl list`. 0 means a clean exit; anything else is how the job failed.")
            }

            if s.keepAlive {
                statusCard("KeepAlive", "On", Color.dsWarning,
                           help: "The plist asks launchd to restart this job whenever it exits. Stopping it in this session is pointless — launchd brings it straight back. Disable Autostart is the way to stop it.")
            }
        }
    }

    private func startsValue(_ s: LaunchdService) -> String {
        if s.disabled { return "Never" }
        return s.runAtLoad ? "At Login" : "On Trigger"
    }

    private func startsColor(_ s: LaunchdService) -> Color {
        if s.disabled { return Color.dsMutedForeground }
        return s.runAtLoad ? Color.dsSuccess : Color.dsPrimary
    }

    private func startsHelp(_ s: LaunchdService) -> String {
        if s.disabled {
            return "Autostart is off — the label is disabled in launchd's override database, which survives a reboot. The plist is still on disk, but launchd will not load it."
        }
        if s.runAtLoad {
            return "The plist sets `RunAtLoad`, so launchd starts this job at every login."
        }
        return "No `RunAtLoad` in the plist — launchd loads this job at login and then waits for its trigger (a socket, a watched path, or a calendar interval) before running it."
    }

    private func statusCard(_ label: String, _ value: String, _ color: Color, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsSecondary, in: RoundedRectangle(cornerRadius: 10))
        .help(help)
    }

    private func cpuColor(_ s: LaunchdService) -> Color {
        guard let cpu = s.cpuPercent else { return Color.dsMutedForeground }
        return cpu >= 50 ? Color.dsWarning : Color.dsPrimary
    }

    // MARK: - Actions

    /// Off writes launchd's override database, on clears it — both survive a reboot.
    private func autostartBinding(_ s: LaunchdService) -> Binding<Bool> {
        let (filePath, label) = (s.filePath, s.label)
        return Binding(
            get: { !s.disabled },
            set: { enabled in
                perform(enabled ? "launchctl enable" : "launchctl disable") {
                    try LaunchdManager.setAutostart(enabled: enabled, filePath: filePath, label: label)
                }
            }
        )
    }

    /// Make it run now: load it first if launchd does not know about it yet. A job
    /// with `RunAtLoad` is already running by then, so the start is best-effort.
    private func activate(_ s: LaunchdService) {
        let (filePath, label) = (s.filePath, s.label)
        let wasLoaded = s.loaded
        perform("Activate") {
            if wasLoaded {
                try LaunchdManager.control(action: .start, filePath: filePath, label: label)
            } else {
                try LaunchdManager.control(action: .load, filePath: filePath, label: label)
                try? LaunchdManager.control(action: .start, filePath: filePath, label: label)
            }
        }
    }

    /// Unload rather than stop: `stop` alone is pointless for a KeepAlive job —
    /// launchd restarts it immediately.
    private func deactivate(_ s: LaunchdService) {
        let (filePath, label) = (s.filePath, s.label)
        perform("Deactivate") {
            try LaunchdManager.control(action: .unload, filePath: filePath, label: label)
        }
    }

    private func perform(_ description: String, _ work: @escaping @Sendable () throws -> Void) {
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try work() }.value
            } catch {
                errorMessage = "\(description) failed: \(error.localizedDescription)"
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
