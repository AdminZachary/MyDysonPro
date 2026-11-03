import Foundation
import CoreLocation

/// Feature 4: records Zone readings with GPS ONLY while "commute recording" is on.
/// Data stays on the device (Documents/commutes.json).
@MainActor
final class CommuteRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = CommuteRecorder()

    @Published private(set) var routes: [CommuteRoute] = []
    @Published private(set) var active: CommuteRoute?
    @Published private(set) var status = "未记录"

    private let lm = CLLocationManager()
    private var lastLocation: CLLocation?
    private var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("commutes.json")
    }

    override private init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        lm.distanceFilter = 15
        lm.activityType = .otherNavigation
        lm.pausesLocationUpdatesAutomatically = false
        if let d = try? Data(contentsOf: url), let r = try? JSONDecoder().decode([CommuteRoute].self, from: d) { routes = r }
    }

    func start(name: String? = nil) {
        guard active == nil else { return }
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"
        active = CommuteRoute(name: name ?? "通勤 \(f.string(from: Date()))", start: Date(),
                              layoutVerified: ZoneAQLayout.current.isVerified)
        lm.requestWhenInUseAuthorization()
        lm.allowsBackgroundLocationUpdates = true      // requires UIBackgroundModes "location"
        lm.showsBackgroundLocationIndicator = true
        lm.startUpdatingLocation()
        status = "记录中"
    }

    func stop() {
        lm.stopUpdatingLocation()
        lm.allowsBackgroundLocationUpdates = false
        guard var r = active else { return }
        r.end = Date()
        active = nil
        if !r.points.isEmpty { routes.insert(r, at: 0); save() }
        status = r.points.isEmpty ? "已停止（没有记录到数据点）" : "已保存 \(r.points.count) 个点"
    }

    func delete(_ r: CommuteRoute) {
        routes.removeAll { $0.id == r.id }
        save()
    }

    func ingest(_ reading: ZoneAQReading) {
        guard active != nil, let loc = lastLocation, Date().timeIntervalSince(loc.timestamp) < 30,
              loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 100 else { return }
        let plausible = reading.looksPlausible
        active?.points.append(CommutePoint(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, date: reading.date,
                                           no2Ppb: plausible ? reading.no2Ppb : nil,
                                           vocPpb: plausible ? reading.vocPpb : nil,
                                           ambientDb: plausible ? reading.ambientDb : nil))
        status = "记录中：\(active?.points.count ?? 0) 个点"
    }

    private func save() {
        if let d = try? JSONEncoder().encode(routes) { try? d.write(to: url, options: .atomic) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in self.lastLocation = l }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.status = "定位失败：\(error.localizedDescription)" }
    }
}
