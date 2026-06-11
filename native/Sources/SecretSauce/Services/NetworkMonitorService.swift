import Foundation

/// Read-only network visibility, the monitoring half of a Little-Snitch-style
/// tool. Snapshots open connections via `lsof`, resolves reverse-DNS through the
/// `host` binary, and (opt-in) geo-locates remote IPs via an online batch lookup.
///
/// This service NEVER blocks traffic. Per-connection enforcement requires a
/// NEFilterDataProvider system extension (Apple-granted entitlement + Developer
/// ID + notarization) — tracked as Phase 2, out of scope for the ad-hoc build.
enum NetworkMonitorService {

    // MARK: - Snapshot

    /// Parses `lsof -nP -i -F pcPnT` into a connection list.
    ///
    /// `-F` emits one field per line, prefixed by a type char:
    ///   p<pid>  c<command>            ← process block header
    ///   f<fd>   P<proto> n<name> T…   ← one file (connection) per `f`
    /// Process-level fields persist until the next `p`.
    static func snapshot() -> [NetworkConnection] {
        guard let out = try? ProcessRunner.run(
            "/usr/sbin/lsof", ["-nP", "-i", "-F", "pcPnT"]
        ) else { return [] }

        var conns: [NetworkConnection] = []
        var pid = 0
        var command = ""

        // Per-connection accumulators, flushed on the next `f`/`p` or at EOF.
        var haveConn = false
        var proto = "", name = "", state = ""

        func flush() {
            guard haveConn, !name.isEmpty else { haveConn = false; return }
            let (local, remoteIP, remotePort) = Self.parseName(name)
            // Keep listeners and peers; drop unbound UDP wildcards ("*:*").
            if remoteIP.isEmpty && (local == "*:*" || local.hasSuffix(":*") && state.isEmpty) {
                // unbound UDP socket — noise, skip
            } else {
                conns.append(NetworkConnection(
                    pid: pid, command: command, proto: proto,
                    localEndpoint: local, remoteIP: remoteIP,
                    remotePort: remotePort, state: state
                ))
            }
            haveConn = false
            proto = ""; name = ""; state = ""
        }

        for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let type = line.first else { continue }
            let val = String(line.dropFirst())
            switch type {
            case "p":
                flush()
                pid = Int(val) ?? 0
            case "c":
                command = val
            case "f":
                flush()
                haveConn = true
            case "P":
                proto = val
            case "n":
                name = val
            case "T":
                // TST=ESTABLISHED, TQR=…, TQS=… — only the state interests us.
                if val.hasPrefix("ST=") { state = String(val.dropFirst(3)) }
            default:
                break
            }
        }
        flush()
        return conns
    }

    /// Splits an lsof `n` field into (localEndpoint, remoteIP, remotePort).
    /// Forms: "1.2.3.4:443->5.6.7.8:55123", "*:57000", "[fe80::1]:62305->[..]:80".
    private static func parseName(_ name: String) -> (String, String, String) {
        let sides = name.components(separatedBy: "->")
        let local = sides[0]
        guard sides.count == 2 else { return (local, "", "") }
        let (ip, port) = splitHostPort(sides[1])
        return (local, ip, port)
    }

    /// Splits "host:port" handling bracketed IPv6 "[::1]:80".
    private static func splitHostPort(_ s: String) -> (String, String) {
        if s.hasPrefix("["), let close = s.firstIndex(of: "]") {
            let ip = String(s[s.index(after: s.startIndex)..<close])
            let rest = s[s.index(after: close)...]
            let port = rest.hasPrefix(":") ? String(rest.dropFirst()) : ""
            return (ip, port)
        }
        guard let colon = s.lastIndex(of: ":") else { return (s, "") }
        return (String(s[..<colon]), String(s[s.index(after: colon)...]))
    }

    // MARK: - Reverse DNS (local, best-effort, cached)

    private static var dnsCache: [String: String] = [:]
    private static let dnsLock = NSLock()

    /// Reverse-DNS one IP via `/usr/bin/host`. Cached; "" cached for no-PTR so we
    /// don't re-query. Runs off the main thread — call from a background Task.
    static func reverseDNS(_ ip: String) -> String? {
        dnsLock.lock(); let cached = dnsCache[ip]; dnsLock.unlock()
        if let cached { return cached.isEmpty ? nil : cached }

        var host = ""
        if let out = try? ProcessRunner.run("/usr/bin/host", ["-W", "1", ip]) {
            // "<ip>.in-addr.arpa domain name pointer example.com."
            if let line = out.split(separator: "\n").first(where: { $0.contains("domain name pointer") }),
               let ptr = line.components(separatedBy: "domain name pointer ").last {
                host = ptr.trimmingCharacters(in: CharacterSet(charactersIn: ". \t"))
            }
        }
        dnsLock.lock(); dnsCache[ip] = host; dnsLock.unlock()
        return host.isEmpty ? nil : host
    }

    // MARK: - Geo lookup (opt-in, online)

    struct GeoInfo: Equatable {
        var countryCode: String
        var country: String
        var city: String
        var lat: Double
        var lon: Double
    }

    private static var geoCache: [String: GeoInfo] = [:]
    private static var ownGeo: GeoInfo?

    /// Geo-locates this machine's public IP (for the "home" pin on the map).
    /// Same opt-in path as lookupGeo — only called from the "Locate IPs" button.
    static func lookupOwnLocation() async throws -> GeoInfo? {
        if let ownGeo { return ownGeo }
        guard let url = URL(string: "http://ip-api.com/json?fields=countryCode,country,city,lat,lon") else { return nil }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let geo = GeoInfo(
            countryCode: (obj["countryCode"] as? String) ?? "",
            country: (obj["country"] as? String) ?? "",
            city: (obj["city"] as? String) ?? "",
            lat: (obj["lat"] as? Double) ?? 0,
            lon: (obj["lon"] as? Double) ?? 0
        )
        if geo.lat != 0 || geo.lon != 0 { ownGeo = geo }
        return ownGeo
    }

    /// Geo-locates up to 100 public IPs in one request via ip-api.com's batch
    /// endpoint. OPT-IN: this is the only path in the app that talks to the
    /// network, and only for IPs the user is already connected to. Returns a
    /// map ip -> GeoInfo (country, city, coordinates). Results cached across calls.
    static func lookupGeo(_ ips: [String]) async throws -> [String: GeoInfo] {
        let unique = Array(Set(ips)).filter { geoCache[$0] == nil }
        if unique.isEmpty { return geoCache }

        for chunk in stride(from: 0, to: unique.count, by: 100).map({
            Array(unique[$0..<min($0 + 100, unique.count)])
        }) {
            guard let url = URL(string: "http://ip-api.com/batch?fields=query,countryCode,country,city,lat,lon") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: chunk)
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            for entry in arr {
                guard let ip = entry["query"] as? String else { continue }
                geoCache[ip] = GeoInfo(
                    countryCode: (entry["countryCode"] as? String) ?? "",
                    country: (entry["country"] as? String) ?? "",
                    city: (entry["city"] as? String) ?? "",
                    lat: (entry["lat"] as? Double) ?? 0,
                    lon: (entry["lon"] as? Double) ?? 0
                )
            }
        }
        return geoCache
    }
}
