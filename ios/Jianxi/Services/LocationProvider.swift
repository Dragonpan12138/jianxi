import CoreLocation
import Foundation

@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationFix, Error>?
    private var timeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func current() async throws -> LocationFix {
        guard CLLocationManager.locationServicesEnabled() else {
            throw ClientError(message: "请先打开手机的位置服务")
        }
        let authorization = manager.authorizationStatus
        guard authorization == .notDetermined || authorization == .authorizedAlways ||
              authorization == .authorizedWhenInUse else {
            throw ClientError(message: "请允许本次定位后继续付款")
        }
        if authorization != .notDetermined, let location = manager.location, isUsable(location) {
            return LocationFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        }
        guard continuation == nil else { throw ClientError(message: "正在获取位置，请稍后") }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeout = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                finish(.failure(ClientError(message: "暂时无法获取位置，请稍后重试")))
            }
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
            default: finish(.failure(ClientError(message: "请允许本次定位后继续付款")))
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted: finish(.failure(ClientError(message: "请允许本次定位后继续付款")))
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last(where: isUsable) else {
            if manager.accuracyAuthorization == .reducedAccuracy {
                finish(.failure(ClientError(message: "请在系统设置中允许精确位置后重试")))
            } else {
                manager.requestLocation()
            }
            return
        }
        finish(.success(LocationFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(ClientError(message: "暂时无法获取位置，请稍后重试")))
    }

    private func isUsable(_ location: CLLocation) -> Bool {
        let age = Date().timeIntervalSince(location.timestamp)
        return (0...300).contains(age) && (0...1500).contains(location.horizontalAccuracy)
    }

    private func finish(_ result: Result<LocationFix, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        continuation.resume(with: result)
    }
}
