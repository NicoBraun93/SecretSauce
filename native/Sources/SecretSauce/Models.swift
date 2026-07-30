import Foundation

struct EnvVar: Identifiable, Equatable {
    var key: String
    var value: String
    var id: String { key }
}

struct LaunchdService: Identifiable, Equatable {
    var label: String
    var filePath: String
    var vars: [EnvVar]
    var program: String
    var loaded: Bool
    var pid: Int?
    var lastExitCode: Int?
    /// Resident set size of the job's whole process tree (bytes), nil when not running.
    var memoryBytes: UInt64?
    /// CPU share of the job's process tree as reported by `ps` — a decaying
    /// average over roughly the last minute, so 200 means two saturated cores.
    var cpuPercent: Double?
    /// Child processes folded into the memory/CPU figures above.
    var childProcessCount: Int = 0
    /// `ps` elapsed time of the main process, e.g. "02:14:07" or "3-01:12:44".
    var uptime: String?
    /// Disabled in launchd's override database. Unlike `unload`, this survives a
    /// reboot, so the job does not come back at the next login.
    var disabled: Bool = false
    /// `RunAtLoad` in the plist: launchd starts the job the moment it is loaded
    /// (i.e. at login) instead of waiting for a socket/path/calendar trigger.
    var runAtLoad: Bool = false
    /// `KeepAlive` in the plist: launchd restarts the job whenever it exits.
    var keepAlive: Bool = false
    var id: String { label }

    /// Whether this job will actually come up by itself at the next login.
    var autostartsAtLogin: Bool { !disabled && runAtLoad }
}

/// A snapshot of system-wide physical memory, derived from `vm_stat` +
/// `sysctl vm.swapusage`. All figures in bytes.
struct SystemMemory: Equatable {
    var total: UInt64
    var wired: UInt64
    var active: UInt64
    var compressed: UInt64
    var inactive: UInt64      // cached / reclaimable
    var free: UInt64
    var swapUsed: UInt64

    /// Memory that is expensive to reclaim (drives the pressure gauge).
    var used: UInt64 { wired + active + compressed }
    var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }

    enum Pressure { case normal, warning, critical }
    var pressure: Pressure {
        switch usedFraction {
        case ..<0.70: return .normal
        case ..<0.85: return .warning
        default: return .critical
        }
    }

    static let zero = SystemMemory(total: 0, wired: 0, active: 0, compressed: 0,
                                   inactive: 0, free: 0, swapUsed: 0)
}

/// A memory consumer for the Overview "top consumers" list. Rows are clustered
/// by their top-level `.app` bundle, so all of an app's helper processes
/// (e.g. every "Google Chrome Helper (Renderer)") roll up into one row.
struct MemoryProcess: Identifiable, Equatable {
    var name: String            // group / display name
    var memoryBytes: UInt64     // summed RSS across the cluster
    var processCount: Int       // number of PIDs folded in
    var bundlePath: String?     // "…/X.app" — enables Show/Quit; nil for daemons
    var id: String { name }

    /// Only app bundles can be shown/quit; system daemons cannot.
    var isApp: Bool { bundlePath != nil }
}

/// Shared human-readable byte formatter (e.g. "1.4 GB", "312 MB").
enum ByteFormat {
    static func string(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowedUnits = [.useMB, .useGB]
        return f.string(fromByteCount: Int64(bytes))
    }
}

/// One open network endpoint, parsed from `lsof -nP -i -F`. Read-only snapshot —
/// monitoring only, no enforcement (see firewall Phase 2).
struct NetworkConnection: Identifiable, Equatable {
    var pid: Int
    var command: String
    var proto: String            // TCP / UDP
    var localEndpoint: String    // host:port (may be *:port)
    var remoteIP: String         // empty for listeners / unbound UDP
    var remotePort: String
    var state: String            // ESTABLISHED, LISTEN, … (empty for UDP)

    /// Stable identity across refreshes so SwiftUI keeps row state.
    var id: String { "\(pid)-\(proto)-\(localEndpoint)-\(remoteIP):\(remotePort)" }

    /// True for a peer we can geo-locate (public, routable, has an IP).
    var isRemote: Bool { !remoteIP.isEmpty && !NetworkConnection.isLocalIP(remoteIP) }

    static func isLocalIP(_ ip: String) -> Bool {
        if ip == "*" || ip.isEmpty { return true }
        if ip.hasPrefix("127.") || ip == "::1" { return true }            // loopback
        if ip.hasPrefix("10.") || ip.hasPrefix("192.168.") { return true } // RFC1918
        if ip.hasPrefix("169.254.") { return true }                        // link-local
        if ip.lowercased().hasPrefix("fe80") || ip.lowercased().hasPrefix("fc")
            || ip.lowercased().hasPrefix("fd") { return true }             // IPv6 local/ULA
        // 172.16.0.0 – 172.31.255.255
        if ip.hasPrefix("172.") {
            let octet = ip.dropFirst(4).prefix { $0 != "." }
            if let n = Int(octet), (16...31).contains(n) { return true }
        }
        return false
    }
}
