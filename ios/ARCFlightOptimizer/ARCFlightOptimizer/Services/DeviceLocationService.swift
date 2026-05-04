import CoreLocation
import Foundation

@MainActor
final class DeviceLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLaunchSite() async throws -> (latitude: Double, longitude: Double, label: String) {
        let location = try await currentLocation()
        let label = await reverseGeocode(location) ?? "Current Location"
        return (location.coordinate.latitude, location.coordinate.longitude, label)
    }

    private func currentLocation() async throws -> CLLocation {
        let status = manager.authorizationStatus
        guard status != .denied && status != .restricted else {
            throw DeviceLocationError.permissionDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                finish(with: .failure(DeviceLocationError.permissionDenied))
            case .notDetermined:
                break
            @unknown default:
                finish(with: .failure(DeviceLocationError.permissionDenied))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.last {
                finish(with: .success(location))
            } else {
                finish(with: .failure(DeviceLocationError.locationUnavailable))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            finish(with: .failure(error))
        }
    }

    private func finish(with result: Result<CLLocation, Error>) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        switch result {
        case .success(let location):
            continuation.resume(returning: location)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func reverseGeocode(_ location: CLLocation) async -> String? {
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return nil
        }
        return [placemark.locality, placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

enum DeviceLocationError: LocalizedError {
    case permissionDenied
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission is needed to pull weather from this iPhone."
        case .locationUnavailable:
            return "The iPhone location is not available right now."
        }
    }
}
