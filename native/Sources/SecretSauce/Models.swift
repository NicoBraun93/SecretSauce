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
    var id: String { label }
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
