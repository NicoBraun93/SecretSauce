import Foundation

/// Read-only system memory visibility for the Overview tab.
///
/// - `snapshot()` parses `vm_stat` (page counts) + `sysctl vm.swapusage` into a
///   `SystemMemory` breakdown. Total comes from `ProcessInfo.physicalMemory`.
/// - `topProcesses(limit:)` aggregates `ps -A -o rss,comm` by command so a
///   multi-process app (e.g. a browser) shows as a single ranked row.
///
/// Nothing here mutates the system; the tab is purely informational plus the
/// launch-agent controls it borrows from `LaunchdManager`.
enum SystemMemoryService {
    static func snapshot() -> SystemMemory {
        let total = ProcessInfo.processInfo.physicalMemory
        let (pageSize, pages) = vmStat()

        func bytes(_ key: String) -> UInt64 { (pages[key] ?? 0) * pageSize }

        // Fold speculative into free and purgeable into reclaimable "inactive",
        // matching how Activity Monitor buckets these.
        let free = bytes("free") + bytes("speculative")
        let wired = bytes("wired down")
        let compressed = bytes("occupied by compressor")
        let active = bytes("active")
        let inactive = bytes("inactive") + bytes("purgeable")

        return SystemMemory(
            total: total,
            wired: wired,
            active: active,
            compressed: compressed,
            inactive: inactive,
            free: free,
            swapUsed: swapUsed()
        )
    }

    static func topProcesses(limit: Int = 8) -> [MemoryProcess] {
        guard let out = try? ProcessRunner.run("/bin/ps", ["-A", "-o", "rss=,comm="]) else {
            return []
        }
        // Cluster by top-level .app bundle so helper processes roll into their app.
        var totals: [String: (rss: UInt64, count: Int, bundle: String?)] = [:]
        for line in out.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let rssKB = UInt64(parts[0]) else { continue }
            let comm = String(parts[1])
            let (name, bundle) = cluster(for: comm)
            let rss = rssKB * 1024
            if let existing = totals[name] {
                totals[name] = (existing.rss + rss, existing.count + 1, existing.bundle ?? bundle)
            } else {
                totals[name] = (rss, 1, bundle)
            }
        }
        return totals
            .map { MemoryProcess(name: $0.key, memoryBytes: $0.value.rss,
                                 processCount: $0.value.count, bundlePath: $0.value.bundle) }
            .sorted { $0.memoryBytes > $1.memoryBytes }
            .prefix(limit)
            .map { $0 }
    }

    /// Derives (displayName, bundlePath) from a process's executable path.
    /// Uses the FIRST `.app` component (the top-level bundle), so nested helper
    /// bundles like ".../Google Chrome Helper (Renderer).app/..." still cluster
    /// under "Google Chrome". Non-app daemons fall back to the binary name.
    private static func cluster(for comm: String) -> (name: String, bundle: String?) {
        let components = comm.split(separator: "/", omittingEmptySubsequences: false)
        var prefix = ""
        for comp in components {
            prefix += "/" + comp
            if comp.hasSuffix(".app") {
                let name = String(comp.dropLast(4))   // strip ".app"
                return (name, prefix)
            }
        }
        return ((comm as NSString).lastPathComponent, nil)
    }

    // MARK: - App controls (Overview actions)

    /// Brings an app to the foreground so the user can see what it is.
    static func showApp(bundlePath: String) throws {
        try ProcessRunner.run("/usr/bin/open", [bundlePath])
    }

    /// Asks an app to quit gracefully (respects unsaved-work prompts). Uses the
    /// bundle name via AppleScript rather than SIGKILL, which would lose data.
    static func quitApp(named name: String) throws {
        try ProcessRunner.run("/usr/bin/osascript", ["-e", "quit app \"\(name)\""])
    }

    // MARK: - Parsing

    /// Returns (pageSize, [statLabel: pageCount]). Labels are the text between
    /// "Pages " and ":" in each `vm_stat` line (e.g. "free", "wired down").
    private static func vmStat() -> (UInt64, [String: UInt64]) {
        guard let out = try? ProcessRunner.run("/usr/bin/vm_stat", []) else { return (4096, [:]) }
        var pageSize: UInt64 = 4096
        var pages: [String: UInt64] = [:]
        for line in out.components(separatedBy: "\n") {
            if line.contains("page size of"),
               let n = line.firstMatch(digitsAfter: "page size of ") {
                pageSize = n
                continue
            }
            guard line.hasPrefix("Pages "), let colon = line.firstIndex(of: ":") else { continue }
            let label = String(line[line.index(line.startIndex, offsetBy: 6)..<colon])
            let valueStr = line[line.index(after: colon)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " .\t"))
            if let count = UInt64(valueStr) { pages[label] = count }
        }
        return (pageSize, pages)
    }

    private static func swapUsed() -> UInt64 {
        // "vm.swapusage: total = 0.00M  used = 512.25M  free = ..."
        guard let out = try? ProcessRunner.run("/usr/sbin/sysctl", ["vm.swapusage"]),
              let range = out.range(of: "used = ") else { return 0 }
        let rest = out[range.upperBound...]
        let token = rest.prefix { $0 != " " }   // e.g. "512.25M"
        return parseSwapToken(String(token))
    }

    private static func parseSwapToken(_ token: String) -> UInt64 {
        guard let unit = token.last else { return 0 }
        let number = Double(token.dropLast()) ?? 0
        let multiplier: Double
        switch unit {
        case "K": multiplier = 1024
        case "M": multiplier = 1024 * 1024
        case "G": multiplier = 1024 * 1024 * 1024
        default:  multiplier = 1
        }
        return UInt64(number * multiplier)
    }
}

private extension String {
    /// Parses the first run of digits appearing after `marker`.
    func firstMatch(digitsAfter marker: String) -> UInt64? {
        guard let r = range(of: marker) else { return nil }
        let digits = self[r.upperBound...].prefix { $0.isNumber }
        return UInt64(digits)
    }
}
