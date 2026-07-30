import Foundation

/// Reads launch agents from ~/Library/LaunchAgents, their runtime status from
/// `launchctl list`, and edits the EnvironmentVariables dict in their plists.
enum LaunchdManager {
    private static var agentsDir: String {
        FileManager.default.homeDirectoryForCurrentUser.path + "/Library/LaunchAgents"
    }

    /// The per-user launchd domain that owns ~/Library/LaunchAgents jobs. No root
    /// needed for enable/disable/bootstrap/bootout inside it.
    private static var guiDomain: String { "gui/\(getuid())" }

    static func list() -> [LaunchdService] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: agentsDir) else { return [] }
        let statuses = launchctlStatuses()
        let processes = processTable()
        let disabled = disabledLabels()

        var services: [LaunchdService] = []
        for f in files.sorted() where f.hasSuffix(".plist") {
            let filePath = "\(agentsDir)/\(f)"
            guard let obj = try? readPlist(filePath) else { continue }

            let label = (obj["Label"] as? String) ?? String(f.dropLast(".plist".count))
            let envObj = (obj["EnvironmentVariables"] as? [String: Any]) ?? [:]
            let vars = envObj
                .map { EnvVar(key: $0.key, value: String(describing: $0.value)) }
                .sorted { $0.key < $1.key }

            let program: String
            if let p = obj["Program"] as? String {
                program = p
            } else if let args = obj["ProgramArguments"] as? [Any] {
                program = args.map { String(describing: $0) }.joined(separator: " ")
            } else {
                program = ""
            }

            let status = statuses[label]
            let tree = status?.pid.map { processes.subtree(of: $0) }
            services.append(LaunchdService(
                label: label,
                filePath: filePath,
                vars: vars,
                program: program,
                loaded: status != nil,
                pid: status?.pid,
                lastExitCode: status?.lastExitCode,
                memoryBytes: tree?.memoryBytes,
                cpuPercent: tree?.cpuPercent,
                childProcessCount: tree?.childCount ?? 0,
                uptime: status?.pid.flatMap { processes.stats[$0]?.uptime },
                disabled: disabled.contains(label),
                runAtLoad: (obj["RunAtLoad"] as? Bool) ?? false,
                // KeepAlive is either a Bool or a dict of conditions.
                keepAlive: (obj["KeepAlive"] as? Bool) ?? (obj["KeepAlive"] != nil)
            ))
        }
        return services
    }

    /// Labels that launchd has recorded as disabled in its override database
    /// (`/var/db/com.apple.xpc.launchd/disabled.<uid>.plist`). Lines look like
    /// `"com.example.agent" => disabled`; older/newer OS builds print `true`.
    private static func disabledLabels() -> Set<String> {
        guard let out = try? ProcessRunner.run("/bin/launchctl", ["print-disabled", guiDomain]) else { return [] }
        var labels: Set<String> = []
        for line in out.components(separatedBy: "\n") {
            guard let arrow = line.range(of: "=>") else { continue }
            let state = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
            guard state == "disabled" || state == "true" else { continue }
            let label = line[..<arrow.lowerBound]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !label.isEmpty { labels.insert(label) }
        }
        return labels
    }

    private static func launchctlStatuses() -> [String: (pid: Int?, lastExitCode: Int?)] {
        guard let out = try? ProcessRunner.run("/bin/launchctl", ["list"]) else { return [:] }
        var statuses: [String: (pid: Int?, lastExitCode: Int?)] = [:]
        for line in out.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3 else { continue }
            let pid = parts[0] == "-" ? nil : Int(parts[0])
            let exitCode = Int(parts[1])
            let label = parts[2].trimmingCharacters(in: .whitespaces)
            statuses[label] = (pid, exitCode)
        }
        return statuses
    }

    struct ProcStats {
        var memoryBytes: UInt64
        var cpuPercent: Double
        var uptime: String
    }

    /// A whole-system process snapshot with parent links, so a job's cost can be
    /// reported for its entire tree — a wrapper script's pid is what launchd
    /// tracks, but the memory and CPU live in the children it spawns.
    struct ProcessSnapshot {
        var stats: [Int: ProcStats] = [:]
        var children: [Int: [Int]] = [:]

        func subtree(of pid: Int) -> (memoryBytes: UInt64, cpuPercent: Double, childCount: Int) {
            var memory: UInt64 = 0
            var cpu = 0.0
            var visited: Set<Int> = []
            var queue = [pid]
            while let current = queue.popLast() {
                guard visited.insert(current).inserted, let s = stats[current] else { continue }
                memory += s.memoryBytes
                cpu += s.cpuPercent
                queue.append(contentsOf: children[current] ?? [])
            }
            return (memory, cpu, max(0, visited.count - 1))
        }
    }

    /// One `ps` call for the whole table: pid, ppid, RSS (KB), %CPU, elapsed time.
    /// `%cpu` on macOS is a decaying average over roughly the last minute, not an
    /// instantaneous sample, so it can exceed 100 on multi-core work.
    private static func processTable() -> ProcessSnapshot {
        guard let out = try? ProcessRunner.run("/bin/ps", ["-A", "-o", "pid=,ppid=,rss=,%cpu=,etime="]) else {
            return ProcessSnapshot()
        }
        var snapshot = ProcessSnapshot()
        for line in out.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 5,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]),
                  let rssKB = UInt64(parts[2]),
                  let cpu = Double(parts[3]) else { continue }
            snapshot.stats[pid] = ProcStats(memoryBytes: rssKB * 1024,
                                            cpuPercent: cpu,
                                            uptime: String(parts[4]))
            snapshot.children[ppid, default: []].append(pid)
        }
        return snapshot
    }

    private static func readPlist(_ filePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let obj = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = obj as? [String: Any] else {
            throw ProcessError.failed(command: "plist", stderr: "\(filePath) is not a dictionary plist")
        }
        return dict
    }

    private static func writePlist(_ filePath: String, _ obj: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: obj, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: filePath))
    }

    static func upsertVar(filePath: String, key: String, value: String) throws {
        var obj = try readPlist(filePath)
        var env = (obj["EnvironmentVariables"] as? [String: Any]) ?? [:]
        env[key] = value
        obj["EnvironmentVariables"] = env
        try writePlist(filePath, obj)
    }

    static func deleteVar(filePath: String, key: String) throws {
        var obj = try readPlist(filePath)
        guard var env = obj["EnvironmentVariables"] as? [String: Any] else { return }
        env.removeValue(forKey: key)
        if env.isEmpty {
            obj.removeValue(forKey: "EnvironmentVariables")
        } else {
            obj["EnvironmentVariables"] = env
        }
        try writePlist(filePath, obj)
    }

    enum Action: String {
        case load, unload, start, stop
    }

    /// Session-scoped controls. `load`/`unload` only touch the *running* launchd
    /// domain: the plist stays in ~/Library/LaunchAgents, so launchd picks it up
    /// again at the next login. Use `setAutostart` for a change that sticks.
    static func control(action: Action, filePath: String, label: String) throws {
        switch action {
        case .load: try ProcessRunner.run("/bin/launchctl", ["load", filePath])
        case .unload: try ProcessRunner.run("/bin/launchctl", ["unload", filePath])
        case .start: try ProcessRunner.run("/bin/launchctl", ["start", label])
        case .stop: try ProcessRunner.run("/bin/launchctl", ["stop", label])
        }
    }

    /// Turns the agent off (or back on) permanently, across reboots.
    ///
    /// `launchctl disable` records the label in launchd's override database, which
    /// outlives a reboot — that is the part `unload` does not do. Disabling alone
    /// does not stop an already-running job, and enabling alone does not start
    /// one, so each branch pairs the override with a bootout/bootstrap. The
    /// bootout/bootstrap half is best-effort: it fails harmlessly when the job is
    /// already in the target state, and the override is what decides the next login.
    static func setAutostart(enabled: Bool, filePath: String, label: String) throws {
        let target = "\(guiDomain)/\(label)"
        if enabled {
            try ProcessRunner.run("/bin/launchctl", ["enable", target])
            _ = try? ProcessRunner.run("/bin/launchctl", ["bootstrap", guiDomain, filePath])
        } else {
            try ProcessRunner.run("/bin/launchctl", ["disable", target])
            _ = try? ProcessRunner.run("/bin/launchctl", ["bootout", target])
        }
    }
}
