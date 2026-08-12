//
//  SpotARScreen.swift
//  FootprintDiary
//
//  [보관] RealityKit AR — 스팟 방향에 랜드마크를 세우고 안개 너머로 찾아가 촬영.
//
//  앱이 '탐험 일지' 한 화면으로 정리되면서 쓰이지 않는다.
//  지우지 않고 통째로 주석 처리해 둔다 — 되살리려면 아래 주석을 벗기고
//  ContentView에서 다시 연결하면 된다. (동작하던 마지막 상태: 커밋 a0de097)
//

/*
//
//  SpotARScreen.swift
//  FootprintDiary
//
//  스팟을 AR로 찾아가서 사진을 찍는 화면.
//
//  ARKit의 지오 앵커(ARGeoTrackingConfiguration)는 한국을 비롯한 많은 나라에서
//  쓸 수 없다. 그래서 위경도에 앵커를 박는 대신, 세션을 나침반에 맞춰 두고
//  (worldAlignment = .gravityAndHeading) 스팟의 방위각을 계산해 그 방향에
//  마커를 띄운다. 어디서나 동작하고, 걸어서 찾아가는 데는 이걸로 충분하다.
//

import SwiftUI
import SwiftData
import CoreLocation

#if !targetEnvironment(simulator)
import RealityKit
import ARKit
import Combine
#endif

struct SpotARScreen: View {
    let spot: PhotoSpot

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var locationManager: LocationManager

    @State private var capturedImage: UIImage?
    @State private var saveError: String?

    #if !targetEnvironment(simulator)
    @StateObject private var capture = ARCaptureController()
    #endif

    /// 지금 위치에서 스팟까지의 거리 (위치를 모르면 nil)
    private var distance: CLLocationDistance? {
        guard let location = locationManager.currentLocation else { return nil }
        return spot.distance(from: location)
    }

    private var canCapture: Bool {
        guard let distance else { return false }
        return distance <= PhotoSpot.captureRadius
    }

    var body: some View {
        ZStack {
            cameraLayer
                .ignoresSafeArea()

            VStack {
                header
                Spacer()
                if let capturedImage {
                    resultCard(capturedImage)
                } else {
                    shutterArea
                }
            }
            .padding()
        }
        .onAppear { locationManager.startLiveUpdates() }
        .onDisappear { locationManager.stopLiveUpdates() }
        .alert("사진을 저장하지 못했어요", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - 카메라 / AR

    @ViewBuilder
    private var cameraLayer: some View {
        #if targetEnvironment(simulator)
        SpotGuideFallbackView(
            spot: spot,
            distance: distance,
            message: "시뮬레이터에서는 AR 카메라를 쓸 수 없어요.\n실기기에서 확인해주세요."
        )
        #else
        if ARWorldTrackingConfiguration.isSupported {
            SpotARContainer(
                target: spot.coordinate,
                userLocation: locationManager.currentLocation,
                kind: spot.landmarkKind,
                controller: capture
            )
        } else {
            SpotGuideFallbackView(
                spot: spot,
                distance: distance,
                message: "이 기기에서는 AR을 쓸 수 없어요."
            )
        }
        #endif
    }

    // MARK: - 화면 위 정보

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label(spot.name, systemImage: spot.symbolName)
                    .font(.headline)
                Text(distanceText)
                    .font(.subheadline)
                    .foregroundStyle(canCapture ? .green : .secondary)
                Label(fogText, systemImage: "cloud.fog.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    private var distanceText: String {
        guard let distance else { return "위치를 찾는 중이에요" }
        if distance <= PhotoSpot.captureRadius { return "도착! 사진을 찍어보세요" }
        if distance < 1_000 { return "\(Int(distance))m 남았어요" }
        return String(format: "%.1fkm 남았어요", distance / 1_000)
    }

    /// 안개는 남은 거리만큼 짙어진다 — 상태를 글로도 알려 준다
    private var fogText: String {
        guard let distance else { return "안개 속" }
        if distance <= PhotoSpot.captureRadius { return "안개가 걷혔어요 · \(spot.landmarkKind.title)" }
        if distance < 400 { return "안개가 걷히는 중" }
        return "안개가 짙어요 — 가까이 갈수록 걷혀요"
    }

    private var shutterArea: some View {
        VStack(spacing: 12) {
            if !canCapture {
                Text("\(Int(PhotoSpot.captureRadius))m 안으로 들어가면 셔터가 열려요")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            Button {
                takePhoto()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                    Circle()
                        .fill(canCapture ? Color.white : Color.white.opacity(0.35))
                        .frame(width: 62, height: 62)
                }
            }
            .disabled(!canCapture)
            .accessibilityLabel("사진 찍기")
        }
    }

    private func resultCard(_ image: UIImage) -> some View {
        VStack(spacing: 12) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            Label("\(spot.name) 수집 완료", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("오늘 일기에 사진이 담겼어요")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("닫기") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - 촬영과 저장

    private func takePhoto() {
        #if targetEnvironment(simulator)
        saveError = "시뮬레이터에는 카메라가 없어요."
        #else
        capture.snapshot { image in
            guard let image else {
                saveError = "카메라 화면을 가져오지 못했어요."
                return
            }
            save(image)
        }
        #endif
    }

    private func save(_ image: UIImage) {
        guard let data = PhotoStore.jpegData(from: image) else {
            saveError = "사진을 변환하지 못했어요."
            return
        }

        spot.photoData = data
        spot.collectedAt = .now

        // 찍은 사진은 그 날 일기에 함께 담긴다 — 일기의 '백지'를 대신 채워 준다
        PhotoStore.attachToDiary(data: data, on: .now, context: modelContext)

        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
            return
        }

        // 여기까지 왔다는 건 실제로 그 자리에 있었다는 뜻이니 발자국도 남긴다
        locationManager.recordCurrentLocation()
        capturedImage = image
    }
}

// MARK: - AR이 없을 때의 안내 화면

/// AR을 쓸 수 없는 환경에서 방향과 거리만 알려준다
struct SpotGuideFallbackView: View {
    let spot: PhotoSpot
    let distance: CLLocationDistance?
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
            VStack(spacing: 16) {
                Image(systemName: spot.symbolName)
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text(spot.name)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                if let distance {
                    Text("\(Int(distance))m 떨어져 있어요")
                        .foregroundStyle(.white.opacity(0.75))
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

// MARK: - RealityKit

#if !targetEnvironment(simulator)

/// AR 화면을 들고 있다가 스냅샷을 찍어 주는 다리 역할
final class ARCaptureController: ObservableObject {
    fileprivate weak var arView: ARView?

    func snapshot(_ completion: @escaping (UIImage?) -> Void) {
        guard let arView else {
            completion(nil)
            return
        }
        arView.snapshot(saveToHDR: false) { image in
            DispatchQueue.main.async { completion(image) }
        }
    }
}

/// 스팟 방향에 랜드마크를 세우고, 남은 거리만큼 안개를 덮는 AR 화면
struct SpotARContainer: UIViewRepresentable {
    let target: CLLocationCoordinate2D
    let userLocation: CLLocation?
    let kind: LandmarkKind
    let controller: ARCaptureController

    /// 실제 거리가 멀어도 랜드마크는 이 거리에 세운다.
    /// 수백 미터 앞에 두면 점처럼 작아져서 방향을 알아볼 수 없다.
    static let landmarkDistance: Float = 12

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)

        let configuration = ARWorldTrackingConfiguration()
        // 나침반에 맞춰 둬야 방위각으로 계산한 방향이 실제 방향과 맞는다
        configuration.worldAlignment = .gravityAndHeading
        configuration.planeDetection = []
        arView.session.run(configuration)

        let coordinator = context.coordinator
        coordinator.target = target
        coordinator.userLocation = userLocation
        coordinator.build(kind: kind, in: arView)
        coordinator.observe(arView)

        controller.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.target = target
        context.coordinator.userLocation = userLocation
        controller.arView = uiView
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.subscription?.cancel()
        uiView.session.pause()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - 장면 관리

    final class Coordinator {
        var target: CLLocationCoordinate2D?
        var userLocation: CLLocation?
        var subscription: (any Cancellable)?

        private var landmarkAnchor: AnchorEntity?
        private var landmark: Entity?
        private var fogAnchor: AnchorEntity?
        private var fogLayers: [ModelEntity] = []
        private var fogOpacity: Float = -1
        private var spin: Float = 0

        /// 안개를 이루는 반투명 판의 수와 깊이.
        /// 여러 겹으로 나눠 두면 걸어갈 때 판 사이가 벌어져 공간감이 생긴다.
        private static let fogLayerDepths: [Float] = [2.5, 4, 5.5, 7, 8.5, 10]
        /// 이 거리(m)부터는 안개가 가장 짙다
        private static let fullFogDistance: Double = 900

        // MARK: 만들기

        func build(kind: LandmarkKind, in arView: ARView) {
            let landmarkAnchor = AnchorEntity(world: .zero)
            let landmark = makeLandmark(kind: kind)
            landmarkAnchor.addChild(landmark)
            arView.scene.addAnchor(landmarkAnchor)
            self.landmarkAnchor = landmarkAnchor
            self.landmark = landmark

            let fogAnchor = AnchorEntity(world: .zero)
            for depth in Self.fogLayerDepths {
                // 멀리 있는 판일수록 시야를 채우려면 커야 한다
                let size = depth * 1.6
                let layer = ModelEntity(
                    mesh: .generatePlane(width: size, height: size),
                    materials: [Self.fogMaterial(opacity: 0)]
                )
                layer.position = SIMD3(0, 0, -depth)
                fogAnchor.addChild(layer)
                fogLayers.append(layer)
            }
            arView.scene.addAnchor(fogAnchor)
            self.fogAnchor = fogAnchor
        }

        /// 상자와 구만으로 조립한 저폴리 랜드마크
        private func makeLandmark(kind: LandmarkKind) -> Entity {
            let root = Entity()
            for piece in kind.pieces {
                let mesh: MeshResource
                switch piece.shape {
                case .box(let size):
                    mesh = .generateBox(size: size, cornerRadius: 0.02)
                case .sphere(let radius):
                    mesh = .generateSphere(radius: radius)
                }
                let model = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: piece.color)])
                model.position = piece.position
                root.addChild(model)
            }
            // 멀리서도 알아볼 수 있게 조금 키운다
            root.scale = SIMD3(repeating: 1.8)
            return root
        }

        private static func fogMaterial(opacity: Float) -> UnlitMaterial {
            var material = UnlitMaterial(color: UIColor(red: 0.85, green: 0.89, blue: 0.94, alpha: 1))
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
            return material
        }

        // MARK: 매 프레임 갱신

        func observe(_ arView: ARView) {
            subscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self, weak arView] event in
                guard let self, let arView else { return }
                self.update(arView, deltaTime: Float(event.deltaTime))
            }
        }

        private func update(_ arView: ARView, deltaTime: Float) {
            let camera = arView.cameraTransform

            // 안개는 늘 카메라 앞을 덮는다
            fogAnchor?.transform = camera

            guard let target, let userLocation else { return }

            let distance = CLLocation(latitude: target.latitude, longitude: target.longitude)
                .distance(from: userLocation)

            // 가까워질수록 걷힌다. 촬영 가능한 거리 안에 들면 완전히 갠다.
            let remaining = max(0, distance - PhotoSpot.captureRadius)
            let density = Float(min(remaining / Self.fullFogDistance, 1))
            applyFog(density: density)

            // 랜드마크는 스팟 방향에, 늘 같은 거리에 세운다
            let bearing = userLocation.coordinate.bearing(to: target) * .pi / 180
            // gravityAndHeading에서는 -Z가 북쪽, +X가 동쪽이다
            let direction = SIMD3<Float>(Float(sin(bearing)), 0, Float(-cos(bearing)))
            landmarkAnchor?.position = camera.translation
                + direction * SpotARContainer.landmarkDistance
                - SIMD3<Float>(0, 1.6, 0)

            // 천천히 돌려서 눈에 띄게 한다
            spin += deltaTime * 0.5
            landmark?.orientation = simd_quatf(angle: spin, axis: SIMD3(0, 1, 0))
        }

        /// 안개 짙기를 바꾼다. 재질을 매 프레임 새로 만들지 않도록 눈에 띄게 달라질 때만 갈아 끼운다.
        private func applyFog(density: Float) {
            guard abs(density - fogOpacity) > 0.02 else { return }
            fogOpacity = density
            // 여러 겹이 겹쳐 쌓이므로 한 겹의 짙기는 낮게 잡는다
            let perLayer = density * 0.22
            let material = Self.fogMaterial(opacity: perLayer)
            for layer in fogLayers {
                layer.model?.materials = [material]
            }
        }
    }
}

#else

/// 시뮬레이터에서는 AR을 만들지 않는다 (같은 이름만 맞춰 둔다)
final class ARCaptureController: ObservableObject {}

#endif
*/
