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
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        context.coordinator.onHover = onHover
        context.coordinator.onSelect = onSelect
        context.coordinator.apply(home: home, endpoints: endpoints, selectedID: selectedID, to: map)
    }

    static func dismantleNSView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.stopDashAnimation()
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

    /// Annotation view with mouse-hover tracking and a selection ring.
    fileprivate final class DotView: MKAnnotationView {
        var hoverChanged: ((Bool) -> Void)?
        private var selectionRing: CAShapeLayer?

        override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
            super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self, userInfo: nil
            ))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func mouseEntered(with event: NSEvent) { hoverChanged?(true) }
        override func mouseExited(with event: NSEvent) { hoverChanged?(false) }

        func attachSelectionRing(_ ring: CAShapeLayer) {
            selectionRing = ring
            ring.isHidden = !isSelected
        }

        override func setSelected(_ selected: Bool, animated: Bool) {
            super.setSelected(selected, animated: animated)
            selectionRing?.isHidden = !selected
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onHover: (MapEndpoint?) -> Void = { _ in }
        var onSelect: (MapEndpoint?) -> Void = { _ in }

        private var contentKey = ""
        private var suppressSelectionCallbacks = false
        private var dashTimer: Timer?
        private var dashPhase: CGFloat = 0
        private var lineRenderers: [MKPolylineRenderer] = []

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
            map.removeOverlays(map.overlays)
            lineRenderers.removeAll()

            var toReselect: MKAnnotation?
            for e in endpoints {
                let a = EndpointAnnotation(endpoint: e)
                map.addAnnotation(a)
                if e.id == selectedID { toReselect = a }
            }
            if let home {
                let h = HomeAnnotation(geo: home)
                map.addAnnotation(h)
                for e in endpoints {
                    var coords = [h.coordinate, e.coordinate]
                    map.addOverlay(MKGeodesicPolyline(coordinates: &coords, count: 2))
                }
            }
            if let toReselect {
                map.selectAnnotation(toReselect, animated: false)
            }

            if map.overlays.isEmpty {
                stopDashAnimation()
            } else {
                startDashAnimation()
            }
        }

        // MARK: Dash flow animation

        private func startDashAnimation() {
            guard dashTimer == nil else { return }
            dashTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.dashPhase -= 0.7
                for r in self.lineRenderers {
                    r.lineDashPhase = self.dashPhase
                    r.setNeedsDisplay(.world)
                }
            }
        }

        func stopDashAnimation() {
            dashTimer?.invalidate()
            dashTimer = nil
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

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            r.strokeColor = ConnectionMapView.brandBlue.withAlphaComponent(0.95)
            r.lineWidth = 2.5
            r.lineDashPattern = [7, 6]
            r.lineCap = .round
            lineRenderers.append(r)
            return r
        }

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
