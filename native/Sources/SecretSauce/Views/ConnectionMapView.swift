import SwiftUI
import MapKit
import AppKit

/// One dot on the map: a distinct remote location and all connections going there.
struct MapEndpoint: Identifiable, Equatable {
    let id: String          // "lat,lon"
    let lat: Double
    let lon: Double
    var city: String
    var countryCode: String
    var connectionCount: Int
    var apps: Set<String>

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

/// Little-Snitch-style traffic map: pulsing "home" pin at your public-IP location,
/// endpoint dots, and animated dashed geodesic arcs from home to each endpoint.
/// Wraps AppKit's MKMapView because SwiftUI's Map (macOS 13 API) cannot draw
/// overlays. Endpoints report hover (info card) and click (table filter) upstream.
struct ConnectionMapView: NSViewRepresentable {
    var home: NetworkMonitorService.GeoInfo?
    var endpoints: [MapEndpoint]
    var selectedID: String?
    var onHover: (MapEndpoint?) -> Void = { _ in }
    var onSelect: (MapEndpoint?) -> Void = { _ in }

    fileprivate static let brandBlue = NSColor(red: 59/255, green: 130/255, blue: 245/255, alpha: 1)
    fileprivate static let homeGreen = NSColor(red: 16/255, green: 185/255, blue: 129/255, alpha: 1)

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsZoomControls = true
        // Germany-centered world view by default.
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.5, longitude: 10.0),
            span: MKCoordinateSpan(latitudeDelta: 75, longitudeDelta: 160)
        ), animated: false)
        context.coordinator.installArcOverlay(on: map)
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        context.coordinator.onHover = onHover
        context.coordinator.onSelect = onSelect
        context.coordinator.apply(home: home, endpoints: endpoints, selectedID: selectedID, to: map)
    }

    static func dismantleNSView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: Annotations

    fileprivate final class HomeAnnotation: NSObject, MKAnnotation {
        let coordinate: CLLocationCoordinate2D
        let info: String
        init(geo: NetworkMonitorService.GeoInfo) {
            coordinate = CLLocationCoordinate2D(latitude: geo.lat, longitude: geo.lon)
            info = "This Mac — \(geo.city), \(geo.countryCode) (public IP location)"
        }
    }

    fileprivate final class EndpointAnnotation: NSObject, MKAnnotation {
        let coordinate: CLLocationCoordinate2D
        let endpoint: MapEndpoint
        init(endpoint: MapEndpoint) {
            coordinate = endpoint.coordinate
            self.endpoint = endpoint
        }
        var info: String {
            let place = endpoint.city.isEmpty ? endpoint.countryCode
                : "\(endpoint.city), \(endpoint.countryCode)"
            let apps = endpoint.apps.sorted().joined(separator: ", ")
            return "\(place) — \(endpoint.connectionCount) connection\(endpoint.connectionCount == 1 ? "" : "s"): \(apps)"
        }
    }

    /// NSTrackingArea retains its owner strongly. With `owner: self` the view
    /// retains the area and the area retains the view — a cycle that leaks every
    /// annotation view (plus its layers). This stand-in owner receives the
    /// enter/exit events and forwards them to the view through a weak reference.
    fileprivate final class HoverOwner: NSObject {
        var onHover: ((Bool) -> Void)?
        @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { onHover?(true) }
        @objc(mouseExited:) func mouseExited(with event: NSEvent) { onHover?(false) }
    }

    /// Annotation view with mouse-hover tracking and a selection ring.
    fileprivate final class DotView: MKAnnotationView {
        var hoverChanged: ((Bool) -> Void)?
        private var selectionRing: CAShapeLayer?
        private let hoverOwner = HoverOwner()

        override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
            super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
            hoverOwner.onHover = { [weak self] inside in self?.hoverChanged?(inside) }
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: hoverOwner, userInfo: nil
            ))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        func attachSelectionRing(_ ring: CAShapeLayer) {
            selectionRing = ring
            ring.isHidden = !isSelected
        }

        override func setSelected(_ selected: Bool, animated: Bool) {
            super.setSelected(selected, animated: animated)
            selectionRing?.isHidden = !selected
        }
    }

    /// Click-through host for the arc shape layer; sits above the map so the
    /// arcs render without touching MapKit's tile pipeline.
    fileprivate final class PassthroughView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onHover: (MapEndpoint?) -> Void = { _ in }
        var onSelect: (MapEndpoint?) -> Void = { _ in }

        private var contentKey = ""
        private var suppressSelectionCallbacks = false

        // Arcs live in one CAShapeLayer hovering above the map instead of
        // MKOverlayRenderers: animating renderers means setNeedsDisplay at frame
        // rate, and each call re-rasterizes overlay tiles at every zoom scale —
        // MapKit's draw queue then grows without bound (the 125 GB swap bug).
        // A shape layer animates lineDashPhase on the GPU with zero redraws.
        private var arcs: [[CLLocationCoordinate2D]] = []
        private weak var arcHost: PassthroughView?
        private let arcLayer = CAShapeLayer()

        func installArcOverlay(on map: MKMapView) {
            let host = PassthroughView(frame: map.bounds)
            host.autoresizingMask = [.width, .height]
            host.wantsLayer = true
            arcLayer.strokeColor = ConnectionMapView.brandBlue.withAlphaComponent(0.95).cgColor
            arcLayer.fillColor = NSColor.clear.cgColor
            arcLayer.lineWidth = 2.5
            arcLayer.lineDashPattern = [7, 6]
            arcLayer.lineCap = .round
            host.layer?.addSublayer(arcLayer)
            map.addSubview(host, positioned: .above, relativeTo: nil)
            arcHost = host
        }

        func teardown() {
            arcLayer.removeAllAnimations()
            arcHost?.removeFromSuperview()
        }

        fileprivate func apply(home: NetworkMonitorService.GeoInfo?, endpoints: [MapEndpoint],
                               selectedID: String?, to map: MKMapView) {
            let key = (home.map { "\($0.lat),\($0.lon)" } ?? "-") + "|"
                + endpoints.map { "\($0.id):\($0.connectionCount)" }.sorted().joined(separator: ",")
            guard key != contentKey else { return }
            contentKey = key

            // Rebuilding annotations fires didDeselect; that must not clear the
            // user's table filter, so callbacks are muted during the swap.
            suppressSelectionCallbacks = true
            defer { suppressSelectionCallbacks = false }

            map.removeAnnotations(map.annotations)

            var toReselect: MKAnnotation?
            for e in endpoints {
                let a = EndpointAnnotation(endpoint: e)
                map.addAnnotation(a)
                if e.id == selectedID { toReselect = a }
            }
            arcs = []
            if let home {
                let h = HomeAnnotation(geo: home)
                map.addAnnotation(h)
                arcs = endpoints.map { Self.geodesicSamples(from: h.coordinate, to: $0.coordinate) }
            }
            if let toReselect {
                map.selectAnnotation(toReselect, animated: false)
            }

            refreshArcPath(on: map)
        }

        // MARK: Arc geometry

        /// Great-circle sample points between two coordinates, reusing
        /// MKGeodesicPolyline's interpolation (it is never added to the map).
        private static func geodesicSamples(from a: CLLocationCoordinate2D,
                                            to b: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
            var pair = [a, b]
            let line = MKGeodesicPolyline(coordinates: &pair, count: 2)
            let count = line.pointCount
            guard count > 2 else { return pair }
            let step = max(1, count / 64)
            var coords: [CLLocationCoordinate2D] = []
            coords.reserveCapacity(count / step + 2)
            var i = 0
            while i < count {
                coords.append(line.points()[i].coordinate)
                i += step
            }
            coords.append(b)
            return coords
        }

        /// Re-projects the cached arcs into view space. Cheap (a few hundred
        /// coordinate conversions), so it can run on every visible-region change.
        fileprivate func refreshArcPath(on map: MKMapView) {
            guard let host = arcHost else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }

            guard !arcs.isEmpty else {
                arcLayer.path = nil
                arcLayer.removeAllAnimations()
                return
            }
            let path = CGMutablePath()
            // An arc crossing the antimeridian jumps across the view; break the
            // line there instead of drawing a horizontal streak.
            let wrapJump = map.bounds.width / 2
            for arc in arcs {
                var prev: CGPoint?
                for coord in arc {
                    let p = map.convert(coord, toPointTo: host)
                    if let prev, abs(p.x - prev.x) < wrapJump {
                        path.addLine(to: p)
                    } else {
                        path.move(to: p)
                    }
                    prev = p
                }
            }
            arcLayer.path = path
            if arcLayer.animation(forKey: "dashFlow") == nil {
                let anim = CABasicAnimation(keyPath: "lineDashPhase")
                anim.fromValue = 0
                anim.toValue = -13          // one dash period (7 + 6)
                anim.duration = 13.0 / 14.0 // matches the old 14 pt/s flow speed
                anim.repeatCount = .infinity
                arcLayer.add(anim, forKey: "dashFlow")
            }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            refreshArcPath(on: mapView)
        }

        // MARK: Selection

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard !suppressSelectionCallbacks else { return }
            if let ep = view.annotation as? EndpointAnnotation { onSelect(ep.endpoint) }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard !suppressSelectionCallbacks else { return }
            if view.annotation is EndpointAnnotation { onSelect(nil) }
        }

        // MARK: Rendering

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let home = annotation as? HomeAnnotation {
                let v = (mapView.dequeueReusableAnnotationView(withIdentifier: "home") as? DotView)
                    ?? DotView(annotation: home, reuseIdentifier: "home")
                v.annotation = home
                configureDot(v, radius: 7, color: ConnectionMapView.homeGreen,
                             pulsing: true, label: "This Mac", count: nil)
                v.hoverChanged = nil
                v.toolTip = home.info
                return v
            }
            if let ep = annotation as? EndpointAnnotation {
                let v = (mapView.dequeueReusableAnnotationView(withIdentifier: "endpoint") as? DotView)
                    ?? DotView(annotation: ep, reuseIdentifier: "endpoint")
                v.annotation = ep
                configureDot(v, radius: 7, color: ConnectionMapView.brandBlue,
                             pulsing: false,
                             label: ep.endpoint.city.isEmpty ? ep.endpoint.countryCode : ep.endpoint.city,
                             count: ep.endpoint.connectionCount > 1 ? ep.endpoint.connectionCount : nil)
                let endpoint = ep.endpoint
                v.hoverChanged = { [weak self] inside in
                    self?.onHover(inside ? endpoint : nil)
                }
                v.toolTip = ep.info
                return v
            }
            return nil
        }

        /// Builds a layer-backed dot with halo, optional pulse ring, count badge,
        /// caption pill, and a (hidden) selection ring. Layer coords are
        /// bottom-left origin.
        private func configureDot(_ view: DotView, radius: CGFloat, color: NSColor,
                                  pulsing: Bool, label: String, count: Int?) {
            let w: CGFloat = 96, h: CGFloat = 44
            view.frame = NSRect(x: 0, y: 0, width: w, height: h)
            view.wantsLayer = true
            guard let root = view.layer else { return }
            root.sublayers?.forEach { $0.removeFromSuperlayer() }
            let scale = NSScreen.main?.backingScaleFactor ?? 2

            let dotCenter = CGPoint(x: w / 2, y: h - radius - 4)

            // Soft halo behind every dot so it stands out against map detail.
            let halo = CAShapeLayer()
            let hr = radius + 5
            halo.path = CGPath(ellipseIn: CGRect(x: -hr, y: -hr, width: hr * 2, height: hr * 2), transform: nil)
            halo.fillColor = color.withAlphaComponent(0.30).cgColor
            halo.position = dotCenter
            root.addSublayer(halo)

            if pulsing {
                let ring = CAShapeLayer()
                let r = radius + 2
                ring.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
                ring.fillColor = color.withAlphaComponent(0.35).cgColor
                ring.position = dotCenter
                root.addSublayer(ring)

                let grow = CABasicAnimation(keyPath: "transform.scale")
                grow.fromValue = 1.0
                grow.toValue = 2.6
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0.9
                fade.toValue = 0.0
                let pulse = CAAnimationGroup()
                pulse.animations = [grow, fade]
                pulse.duration = 1.8
                pulse.repeatCount = .infinity
                ring.add(pulse, forKey: "pulse")
            }

            let dot = CAShapeLayer()
            dot.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
            dot.fillColor = color.cgColor
            dot.strokeColor = NSColor.white.cgColor
            dot.lineWidth = 1.8
            dot.position = dotCenter
            root.addSublayer(dot)

            // Selection ring, shown only while the dot is clicked/selected.
            let sel = CAShapeLayer()
            let sr = radius + 4
            sel.path = CGPath(ellipseIn: CGRect(x: -sr, y: -sr, width: sr * 2, height: sr * 2), transform: nil)
            sel.fillColor = NSColor.clear.cgColor
            sel.strokeColor = NSColor.white.cgColor
            sel.lineWidth = 2
            sel.position = dotCenter
            root.addSublayer(sel)
            view.attachSelectionRing(sel)

            if let count {
                let badge = CATextLayer()
                badge.string = "\(count)"
                badge.font = NSFont.boldSystemFont(ofSize: 7)
                badge.fontSize = 7
                badge.foregroundColor = NSColor.white.cgColor
                badge.alignmentMode = .center
                badge.contentsScale = scale
                badge.frame = CGRect(x: dotCenter.x - radius, y: dotCenter.y - 3.5, width: radius * 2, height: 8)
                root.addSublayer(badge)
            }

            let caption = CATextLayer()
            caption.string = label
            caption.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
            caption.fontSize = 9
            caption.foregroundColor = NSColor.white.cgColor
            caption.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
            caption.alignmentMode = .center
            caption.cornerRadius = 6
            caption.contentsScale = scale
            let captionWidth = min(w, CGFloat(label.count) * 6 + 14)
            caption.frame = CGRect(x: (w - captionWidth) / 2, y: dotCenter.y - radius - 18, width: captionWidth, height: 13)
            root.addSublayer(caption)
        }
    }
}
