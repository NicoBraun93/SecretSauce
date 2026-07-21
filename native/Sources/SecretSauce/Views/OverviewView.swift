import SwiftUI

/// RAM-focused dashboard: system memory pressure, the memory footprint of the
/// user's own launch agents (with inline Stop to reclaim RAM), and the biggest
/// system-wide memory consumers for context. Read-only except for the launch
/// agent controls it borrows from `LaunchdManager`. No polling — snapshots on
/// appear and on Refresh, mirroring the Network tab.
struct OverviewView: View {
    @State private var memory: SystemMemory = .zero
    @State private var agents: [LaunchdService] = []
    @State private var processes: [MemoryProcess] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var pendingQuit: MemoryProcess?

    /// Loaded launch agents that currently hold resident memory, biggest first.
    private var runningAgents: [LaunchdService] {
        agents
            .filter { ($0.memoryBytes ?? 0) > 0 }
            .sorted { ($0.memoryBytes ?? 0) > ($1.memoryBytes ?? 0) }
    }

    private var agentsTotal: UInt64 {
        runningAgents.reduce(0) { $0 + ($1.memoryBytes ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                pressureCard
                agentsCard
                processesCard
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .errorAlert($errorMessage)
        .confirmationDialog(
            "Quit \(pendingQuit?.name ?? "")?",
            isPresented: Binding(get: { pendingQuit != nil }, set: { if !$0 { pendingQuit = nil } }),
            presenting: pendingQuit
        ) { proc in
            Button("Quit \(proc.name)", role: .destructive) { quit(proc) }
            Button("Cancel", role: .cancel) { pendingQuit = nil }
        } message: { proc in
            Text("Asks \(proc.name) to quit its \(proc.processCount) process(es), freeing \(ByteFormat.string(proc.memoryBytes)). Save your work first — the app may prompt before closing.")
        }
        .onAppear { load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Memory Overview").font(.title2.weight(.semibold))
                Text("Live snapshot of RAM pressure and what is using it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") { load() }
                .controlSize(.large)
                .disabled(loading)
        }
    }

    // MARK: - Pressure

    private var pressureColor: Color {
        switch memory.pressure {
        case .normal: return .dsSuccess
        case .warning: return .dsWarning
        case .critical: return .dsDanger
        }
    }

    private var pressureLabel: String {
        switch memory.pressure {
        case .normal: return "Normal"
        case .warning: return "Elevated"
        case .critical: return "Critical"
        }
    }

    private var pressureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Memory Pressure").font(.headline)
                Spacer()
                Text(pressureLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pressureColor)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(pressureColor.opacity(0.15), in: Capsule())
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(Int((memory.usedFraction * 100).rounded()))%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(pressureColor)
                    .monospacedDigit()
                Text("of \(ByteFormat.string(memory.total)) used")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            compositionBar
            legend

            if memory.swapUsed > 0 {
                Text("Swap in use: \(ByteFormat.string(memory.swapUsed)) — the system is offloading memory to disk.")
                    .font(.caption)
                    .foregroundStyle(Color.dsWarning)
            }
        }
        .cardStyle()
    }

    private var compositionBar: some View {
        GeometryReader { geo in
            let total = max(memory.total, 1)
            HStack(spacing: 0) {
                segment(memory.wired, total, geo.size.width, .dsPrimary)
                segment(memory.active, total, geo.size.width, .dsSuccess)
                segment(memory.compressed, total, geo.size.width, .dsWarning)
                segment(memory.inactive, total, geo.size.width, .dsMutedForeground.opacity(0.5))
                // Free fills the remainder via the track background.
            }
        }
        .frame(height: 14)
        .background(Color.dsMutedForeground.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func segment(_ value: UInt64, _ total: UInt64, _ width: CGFloat, _ color: Color) -> some View {
        color.frame(width: width * CGFloat(value) / CGFloat(total))
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem("Wired", memory.wired, .dsPrimary)
            legendItem("Active", memory.active, .dsSuccess)
            legendItem("Compressed", memory.compressed, .dsWarning)
            legendItem("Cached", memory.inactive, .dsMutedForeground.opacity(0.5))
            legendItem("Free", memory.free, .dsMutedForeground.opacity(0.18))
        }
    }

    private func legendItem(_ label: String, _ value: UInt64, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(ByteFormat.string(value)).font(.caption.monospacedDigit())
            }
        }
    }

    // MARK: - Launch agents

    private var agentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Launch Agents").font(.headline)
                Spacer()
                Text("\(runningAgents.count) running · \(ByteFormat.string(agentsTotal))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if runningAgents.isEmpty {
                Text("None of your launch agents are currently resident in memory.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Stop an agent to reclaim its memory. It stays installed and can be restarted from the Launchd Services tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(runningAgents) { agent in
                    agentRow(agent)
                }
            }
        }
        .cardStyle()
    }

    private func agentRow(_ agent: LaunchdService) -> some View {
        HStack(spacing: 10) {
            memoryDot(agent.memoryBytes ?? 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.label).lineLimit(1).truncationMode(.middle)
                if agent.pid != nil {
                    Text("PID \(agent.pid!)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(ByteFormat.string(agent.memoryBytes ?? 0))
                .font(.callout.monospacedDigit().weight(.medium))
            if agent.pid != nil {
                Button("Stop") { control(.stop, agent) }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .overlay(Divider(), alignment: .bottom)
    }

    /// Colors a leading dot by how heavy the process is (relative to the biggest).
    private func memoryDot(_ bytes: UInt64) -> some View {
        let heaviest = runningAgents.first?.memoryBytes ?? 1
        let ratio = Double(bytes) / Double(max(heaviest, 1))
        let color: Color = ratio > 0.66 ? .dsDanger : ratio > 0.33 ? .dsWarning : .dsSuccess
        return Circle().fill(color).frame(width: 8, height: 8)
    }

    // MARK: - System processes

    private var processesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Memory Consumers (System-wide)").font(.headline)
            Text("Clustered by app — all of an app's helper processes counted together.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(processes) { proc in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(proc.name).lineLimit(1).truncationMode(.middle)
                        if proc.processCount > 1 {
                            Text("\(proc.processCount) processes")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(ByteFormat.string(proc.memoryBytes))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if proc.isApp {
                        Button("Show") { show(proc) }
                            .controlSize(.small)
                        Button("Quit") { pendingQuit = proc }
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 4)
                .overlay(Divider(), alignment: .bottom)
            }
        }
        .cardStyle()
    }

    // MARK: - Actions

    private func control(_ action: LaunchdManager.Action, _ s: LaunchdService) {
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try LaunchdManager.control(action: action, filePath: s.filePath, label: s.label)
                }.value
            } catch {
                errorMessage = "launchctl \(action.rawValue) failed: \(error.localizedDescription)"
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            load()
        }
    }

    private func show(_ proc: MemoryProcess) {
        guard let path = proc.bundlePath else { return }
        do { try SystemMemoryService.showApp(bundlePath: path) }
        catch { errorMessage = "Could not show \(proc.name): \(error.localizedDescription)" }
    }

    private func quit(_ proc: MemoryProcess) {
        pendingQuit = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try SystemMemoryService.quitApp(named: proc.name)
                }.value
            } catch {
                errorMessage = "Could not quit \(proc.name): \(error.localizedDescription)"
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            load()
        }
    }

    private func load() {
        loading = true
        Task {
            let snap = await Task.detached(priority: .userInitiated) {
                (SystemMemoryService.snapshot(), LaunchdManager.list(), SystemMemoryService.topProcesses())
            }.value
            memory = snap.0
            agents = snap.1
            processes = snap.2
            loading = false
        }
    }
}

private extension View {
    /// Shared card chrome used by the Overview sections.
    func cardStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.dsBorder))
    }
}
