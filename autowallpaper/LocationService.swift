//
//  LocationService.swift
//  autowallpaper
//
//  Created by Antigravity on 2026/11/18.
//

import Foundation
import CoreLocation
import Combine

/// 负责获取系统定位及反向地理编码的城市名称
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var detectedCoordinate: CLLocationCoordinate2D?
    @Published var detectedPlaceName: String?
    @Published var isLocating: Bool = false
    @Published var errorMessage: String?

    var onLocationUpdated: ((Double, Double, String?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = manager.authorizationStatus
    }

    func requestCurrentLocation() {
        errorMessage = nil
        isLocating = true

        let status = manager.authorizationStatus
        authorizationStatus = status

        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            manager.startUpdatingLocation()
        case .authorizedAlways, .authorized:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            isLocating = false
            errorMessage = "定位权限未开启，请在「系统设置 > 隐私与安全性 > 定位服务」中允许本应用访问位置，或直接选择预设城市。"
        @unknown default:
            manager.startUpdatingLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorized || status == .authorizedAlways {
                self.manager.startUpdatingLocation()
            } else if status == .denied || status == .restricted {
                self.isLocating = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let lat = latest.coordinate.latitude
        let lon = latest.coordinate.longitude

        Task { @MainActor in
            self.manager.stopUpdatingLocation()
            self.detectedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            self.isLocating = false

            do {
                let placemarks = try await self.geocoder.reverseGeocodeLocation(latest)
                let place = placemarks.first
                let city = place?.locality ?? place?.administrativeArea ?? place?.name
                self.detectedPlaceName = city
                self.onLocationUpdated?(lat, lon, city)
            } catch {
                self.onLocationUpdated?(lat, lon, nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let desc = error.localizedDescription
        Task { @MainActor in
            self.isLocating = false
            self.errorMessage = "定位获取失败：\(desc)"
        }
    }
}
