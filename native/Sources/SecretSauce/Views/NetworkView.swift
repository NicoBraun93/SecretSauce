import SwiftUI

/// Live network monitor — the "where am I connected" half of a Little-Snitch-style
/// tool. Read-only: shows which process talks to which remote IP / host / country,
/// with a world map of resolved endpoints and animated connection arcs.
/// No blocking (that needs a system extension — Phase 2).
struct NetworkView: View {
    @State private var conns: [NetworkConnection] = []
    @State private var hostsByIP: [String: String] = [:]   // "" = no PTR record
    @State private var geoByIP: [String: NetworkMonitorService.GeoInfo] = [:]
    @State private var ownLocation: NetworkMonitorService.GeoInfo?
    @State private var search = ""
    @State private var groupByApp = true
    @State private var remoteOnly = true
    @State private var showMap = true
    @State private var loading = true
    @State private var resolvingGeo = false
    @State private var errorMessage: String?
    @State private var hoveredEndpoint: MapEndpoint?
    @State private var selectedLocationKey: String?

    /// "lat,lon" geo key for a connection's remote IP — matches MapEndpoint.id.
    private func geoKey(_ c: NetworkConnection) -> String? {
        geoByIP[c.remoteIP].map { "\($0.lat),\($0.lon)" }
    }

    /// Search + remote-only filtering. The map shows these; the clicked-dot
    /// location filter applies only to the table so other pins stay visible.
    private var baseFiltered: [NetworkConnection] {
        var rows = conns
        if remoteOnly { rows = rows.filter(\.isRemote) }
        if !search.isEmpty {
            let q = search.lowercased()
            rows = rows.filter {
                $0.command.lowercased().contains(q)
                    || $0.remoteIP.lowercased().contains(q)
                    || (hostsByIP[$0.remoteIP]?.lowercased().contains(q) ?? false)
                    || (geoByIP[$0.remoteIP].map {
                        $0.country.lowercased().contains(q)
                            || $0.countryCode.lowercased().contains(q)
                            || $0.city.lowercased().contains(q)
                    } ?? false)
            }
        }
        return rows.sorted {
            $0.command.localizedCaseInsensitiveCompare($1.command) == .orderedAscending
        }
    }

    private var filtered: [NetworkConnection] {
        guard let key = selectedLocationKey else { return baseFiltered }
        return baseFiltered.filter { geoKey($0) == key }
    }

    private var grouped: [(app: String, rows: [NetworkConnection])] {
        Dictionary(grouping: filtered, by: \.command)
            .map { (app: $0.key, rows: $0.value) }
            .sorted { $0.app.localizedCaseInsensitiveCompare($1.app) == .orderedAscending }
    }

    /// One map dot per distinct location among currently visible remote connections.
    private var mapEndpoints: [MapEndpoint] {
        var byLocation: [String: MapEndpoint] = [:]
        for c in baseFiltered {
            guard let geo = geoByIP[c.remoteIP], geo.lat != 0 || geo.lon != 0 else { continue }
            let key = "\(geo.lat),\(geo.lon)"
            if var pin = byLocation[key] {
                pin.connectionCount += 1
                pin.apps.insert(c.command)
                byLocation[key] = pin
            } else {
                byLocation[key] = MapEndpoint(
                    id: key, lat: geo.lat, lon: geo.lon,
                    city: geo.city, countryCode: geo.countryCode,
                    connectionCount: 1, apps: [c.command]
                )
            }
        }
        return Array(byLocation.values)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if showMap {
                mapPanel
                Divider()
            }
            searchBar
            Divider()
            tableArea
        }
        .errorAlert($errorMessage)
        .onAppear { refreshOnce() }
    }

    // MARK: Toolbar

    private var establishedCount: Int { filtered.filter { $0.state == "ESTABLISHED" }.count }
    private var listenCount: Int { conns.filter { $0.state == "LISTEN" }.count }
    private var countryCount: Int {
        Set(filtered.compactMap { geoByIP[$0.remoteIP]?.countryCode }.filter { !$0.isEmpty }).count
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Network Monitor").font(.headline)
                HStack(spacing: 6) {
                    summaryChip("\(establishedCount) active", .dsSuccess)
                    summaryChip("\(listenCount) listening", .dsPrimary)
                    if countryCount > 0 {
                        summaryChip("\(countryCount) countries", .dsWarning)
                    }
                    Text("read-only").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle(isOn: $showMap) { Image(systemName: "map") }
                .toggleStyle(.button).controlSize(.small)
                .help("Show world map of resolved endpoints")
            Button {
                refreshOnce()
            } label: {
                if resolvingGeo {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .controlSize(.small)
            .disabled(resolvingGeo)
            .help("Re-snapshots connections and locates remote IPs via ip-api.com — the app's only off-device traffic.")
        }
        .padding(10)
    }

    private func summaryChip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: Map

    private var mapPanel: some View {
        ZStack(alignment: .bottomLeading) {
            ConnectionMapView(
                home: ownLocation,
                endpoints: mapEndpoints,
                selectedID: selectedLocationKey,
                onHover: { hoveredEndpoint = $0 },
                onSelect: { selectedLocationKey = $0?.id }
            )
            if mapEndpoints.isEmpty {
                Text(resolvingGeo ? "Locating your connections…" : "No located connections yet — press Refresh.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(10)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let ep = hoveredEndpoint
                ?? mapEndpoints.first(where: { $0.id == selectedLocationKey }) {
                endpointCard(ep)
            }
        }
        .frame(height: 240)
    }

    /// Info card shown while hovering a dot (or while one is selected):
    /// place, count, and the actual connections going there.
    private func endpointCard(_ ep: MapEndpoint) -> some View {
        let rows = baseFiltered.filter { geoKey($0) == ep.id }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(Self.flag(ep.countryCode))
                Text(ep.city.isEmpty ? ep.countryCode : ep.city)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 8)
                summaryChip("\(rows.count)", .dsPrimary)
            }
            Divider()
            ForEach(rows.prefix(6)) { c in
                HStack(spacing: 6) {
                    appIcon(for: c.pid, size: 13)
                    Text(c.command).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text("\(c.remoteIP):\(c.remotePort)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                .font(.caption)
            }
            if rows.count > 6 {
                Text("+ \(rows.count - 6) more — click the dot to filter the table")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if selectedLocationKey != ep.id {
                Text("Click the dot to filter the table")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(width: 280, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(10)
        .allowsHitTesting(false)
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.dsMutedForeground)
                TextField("Filter by app, IP, host, city, or country…", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color.dsSecondary, in: RoundedRectangle(cornerRadius: 8))
            if let key = selectedLocationKey {
                let ep = mapEndpoints.first { $0.id == key }
                Button {
                    selectedLocationKey = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                        Text(ep.map { $0.city.isEmpty ? $0.countryCode : $0.city } ?? "Location")
                        Image(systemName: "xmark.circle.fill").opacity(0.6)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.dsPrimary.opacity(0.18), in: Capsule())
                    .foregroundStyle(Color.dsPrimary)
                }
                .buttonStyle(.plain)
                .help("Table is filtered to this location — click to clear")
            }
            Toggle("Remote only", isOn: $remoteOnly).controlSize(.small)
            Toggle("Group by app", isOn: $groupByApp).controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: Table

    /// Column widths derived from the available width so the table compresses
    /// gracefully instead of clipping when the window is squeezed.
    private struct ColWidths {
        let proto: CGFloat = 48
        let port: CGFloat = 46
        let state: CGFloat = 92
        var app: CGFloat
        var ip: CGFloat
        var host: CGFloat
        var location: CGFloat

        init(total: CGFloat) {
            let avail = max(total - proto - port - state - 48, 400)
            app = min(220, max(96, avail * 0.26))
            ip = min(150, max(104, avail * 0.24))
            location = min(170, max(86, avail * 0.20))
            host = max(104, avail - app - ip - location)
        }
    }

    private var tableArea: some View {
        GeometryReader { geo in
            let w = ColWidths(total: geo.size.width)
            VStack(spacing: 0) {
                header(w)
                Divider()
                if loading && conns.isEmpty {
                    Spacer(); HStack { Spacer(); ProgressView(); Spacer() }; Spacer()
                } else if filtered.isEmpty {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("No active connections.").foregroundStyle(.secondary)
                        Spacer()
                    }
                    Spacer()
                } else {
                    connectionList(w)
                }
            }
        }
    }

    private func header(_ w: ColWidths) -> some View {
        HStack(spacing: 0) {
            cell("APP", w.app)
            cell("PROTO", w.proto)
            cell("REMOTE IP", w.ip)
            cell("HOST", w.host)
            cell("PORT", w.port)
            cell("LOCATION", w.location)
            cell("STATE", w.state)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    @ViewBuilder
    private func connectionList(_ w: ColWidths) -> some View {
        if groupByApp {
            List {
                ForEach(grouped, id: \.app) { group in
                    Section {
                        ForEach(group.rows) { row(for: $0, w) }
                    } header: {
                        HStack(spacing: 6) {
                            appIcon(for: group.rows.first?.pid, size: 16)
                            Text(group.app).font(.callout.weight(.semibold))
                            Text("\(group.rows.count)")
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Color.dsSecondary, in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
        } else {
            List(filtered) { row(for: $0, w) }
                .listStyle(.plain)
        }
    }

    private func row(for c: NetworkConnection, _ w: ColWidths) -> some View {
        let geo = geoByIP[c.remoteIP]
        let host = hostsByIP[c.remoteIP]
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                if !groupByApp { appIcon(for: c.pid, size: 16) }
                Text(c.command).lineLimit(1).truncationMode(.middle)
            }
            .frame(width: w.app, alignment: .leading)
            cell(c.proto, w.proto)
            cell(c.remoteIP.isEmpty ? "—" : c.remoteIP, w.ip)
            Text(hostDisplay(host, c))
                .lineLimit(1).truncationMode(.middle)
                .foregroundStyle(host?.isEmpty == false ? Color.dsForeground : Color.dsMutedForeground)
                .frame(width: w.host, alignment: .leading)
            cell(c.remotePort.isEmpty ? "—" : c.remotePort, w.port)
            HStack(spacing: 4) {
                if let geo, !geo.countryCode.isEmpty {
                    Text(Self.flag(geo.countryCode))
                    Text(geo.city.isEmpty ? geo.country : geo.city)
                        .lineLimit(1).truncationMode(.tail)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .frame(width: w.location, alignment: .leading)
            stateBadge(c.state).frame(width: w.state, alignment: .leading)
        }
        .font(.system(.callout, design: .monospaced))
        .listRowInsets(EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12))
        .textSelection(.enabled)
    }

    private func hostDisplay(_ host: String?, _ c: NetworkConnection) -> String {
        if let host { return host.isEmpty ? "—" : host }
        return c.isRemote ? "…" : "—"
    }

    /// Icon of the owning process (GUI apps have real icons; daemons get a gear).
    private func appIcon(for pid: Int?, size: CGFloat) -> some View {
        let image = pid.flatMap { NSRunningApplication(processIdentifier: pid_t($0))?.icon }
        return Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "gearshape.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.dsMutedForeground)
                    .padding(2)
            }
        }
        .frame(width: size, height: size)
    }

    private func cell(_ text: String, _ width: CGFloat) -> some View {
        Text(text)
            .lineLimit(1).truncationMode(.middle)
            .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func stateBadge(_ state: String) -> some View {
        if state.isEmpty {
            Text("—").foregroundStyle(.secondary)
        } else {
            let color: Color = state == "ESTABLISHED" ? .dsSuccess
                : state == "LISTEN" ? .dsPrimary : .dsWarning
            Text(state == "ESTABLISHED" ? "ACTIVE" : state)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(color.opacity(0.18), in: Capsule())
                .foregroundStyle(color)
        }
    }

    // MARK: Data

    private func refreshOnce() { Task { await refresh() } }

    /// One snapshot per tab-open or refresh-button press — no polling.
    private func refresh() async {
        let snap = await Task.detached(priority: .userInitiated) {
            NetworkMonitorService.snapshot()
        }.value
        conns = snap
        loading = false
        resolveHostsInBackground()
        // Geo-locate the snapshot so the map fills in on tab open and stays
        // current on refresh (cached IPs don't re-hit the network).
        await resolveGeo()
    }

    /// Best-effort reverse-DNS for remote IPs we haven't resolved yet (local only).
    private func resolveHostsInBackground() {
        let unresolved = Set(
            conns.filter { $0.isRemote && hostsByIP[$0.remoteIP] == nil }.map(\.remoteIP)
        )
        guard !unresolved.isEmpty else { return }
        Task.detached(priority: .utility) {
            for ip in unresolved {
                let host = NetworkMonitorService.reverseDNS(ip)
                await MainActor.run { hostsByIP[ip] = host ?? "" }
            }
        }
    }

    private func resolveGeo() async {
        resolvingGeo = true
        defer { resolvingGeo = false }
        do {
            async let own = NetworkMonitorService.lookupOwnLocation()
            let ips = conns.filter(\.isRemote).map(\.remoteIP)
            if !ips.isEmpty {
                geoByIP = try await NetworkMonitorService.lookupGeo(ips)
            }
            ownLocation = try await own
        } catch {
            errorMessage = "IP location lookup failed: \(error.localizedDescription)"
        }
    }

    /// ISO 3166-1 alpha-2 → regional-indicator flag emoji.
    private static func flag(_ code: String) -> String {
        let base: UInt32 = 0x1F1E6
        var s = ""
        for u in code.uppercased().unicodeScalars where ("A"..."Z").contains(u) {
            if let scalar = Unicode.Scalar(base + (u.value - 65)) { s.unicodeScalars.append(scalar) }
        }
        return s
    }
}
