//
//  MapProxy.swift
//  FootprintDiary
//
//  SwiftUI 쪽에서 지도를 만지고, 지도의 배율을 되돌려 받기 위한 손잡이.
//
//  MKMapView는 UIKit 뷰라 SwiftUI 본문에서 직접 잡을 수 없다. 확대·축소 단추를 누르거나
//  지금 배율이 얼마인지 보여 주려면 그 사이를 이어 줄 것이 하나 필요하다.
//

import Foundation
import MapKit

@MainActor
final class MapProxy: ObservableObject {
    /// 지도는 지도가 갖고, 여기서는 빌려 쓰기만 한다
    weak var mapView: MKMapView?

    /// 화면 한 점(pt)이 실제로 몇 미터인지. 눈금자를 그리는 데 쓴다.
    @Published private(set) var metersPerPoint: CLLocationDistance = 0

    /// 한 번에 얼마나 확대·축소할지
    static let zoomStep: Double = 2

    /// 너무 좁히거나 너무 넓히지 않도록 자른다 (위도 기준 각도)
    static let minimumSpan: CLLocationDegrees = 0.0008   // 약 90m
    static let maximumSpan: CLLocationDegrees = 90

    func report(_ mapView: MKMapView) {
        let width = mapView.bounds.width
        guard width > 0 else { return }
        let meters = MKMetersPerMapPointAtLatitude(mapView.region.center.latitude)
            * mapView.visibleMapRect.size.width
        let value = meters / width
        // 아주 작은 흔들림까지 새로 알리면 화면이 계속 다시 그려진다
        guard abs(value - metersPerPoint) > metersPerPoint * 0.01 || metersPerPoint == 0 else { return }
        metersPerPoint = value
    }

    func zoomIn() { zoom(by: 1 / Self.zoomStep) }
    func zoomOut() { zoom(by: Self.zoomStep) }

    private func zoom(by factor: Double) {
        guard let mapView else { return }
        var region = mapView.region
        let latitude = min(max(region.span.latitudeDelta * factor, Self.minimumSpan), Self.maximumSpan)
        let longitude = min(max(region.span.longitudeDelta * factor, Self.minimumSpan), Self.maximumSpan)
        region.span = MKCoordinateSpan(latitudeDelta: latitude, longitudeDelta: longitude)
        mapView.setRegion(region, animated: true)
    }

    // MARK: - 눈금자

    /// 눈금자 막대의 최대 길이(pt)
    static let scaleBarMaxWidth: CGFloat = 72

    /// 막대가 나타낼 '떨어지는' 거리(m). 1·2·5 × 10ⁿ 중에서 고른다.
    /// 눈금에 '137m' 같은 숫자가 적혀 있으면 눈대중으로 쓸 수 없다.
    var scaleDistance: CLLocationDistance {
        let maximum = Double(Self.scaleBarMaxWidth) * metersPerPoint
        guard maximum > 0 else { return 0 }
        let base = pow(10, floor(log10(maximum)))
        for factor in [5.0, 2.0, 1.0] where base * factor <= maximum {
            return base * factor
        }
        return base
    }

    /// 그 거리를 나타내는 막대의 길이(pt)
    var scaleBarWidth: CGFloat {
        guard metersPerPoint > 0 else { return 0 }
        return CGFloat(scaleDistance / metersPerPoint)
    }

    var scaleText: String {
        let distance = scaleDistance
        guard distance > 0 else { return "" }
        return distance < 1_000
            ? "\(Int(distance))m"
            : (distance < 10_000
               ? String(format: "%.1fkm", distance / 1_000)
               : "\(Int(distance / 1_000))km")
    }
}
