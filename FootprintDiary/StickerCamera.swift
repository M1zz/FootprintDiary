//
//  StickerCamera.swift
//  FootprintDiary
//
//  스티커를 찍는 카메라 — 미리보기와 한 장 찍기.
//
//  StampCamera(펀칭) 앱에서 가져와 이 앱에 필요한 만큼만 남겼다. 저쪽에 있던 '움직이는
//  우표'(연속 프레임)는 데려오지 않았다 — 여기서 만드는 것은 지도에 얹을 손톱만 한 심볼
//  하나이고, 그것이 움직일 까닭이 없다.
//
//  줌은 한 번 걷어 냈다가 되돌렸다. 30pt짜리 그림에 배율은 아무 뜻이 없다고 보았는데,
//  겨누는 쪽에서 보면 이야기가 다르다. 찍고 싶은 것은 길 건너 간판이거나 유리 너머에
//  놓인 물건이라 발로 다가갈 수 없는 일이 잦고, 창은 화면의 일부뿐이라 멀리 있는 것은
//  창 안에서 점이 된다. 배율은 화질을 위한 것이 아니라 손이 닿지 않는 것에 닿기 위한
//  것이다.
//
//  배율은 device.videoZoomFactor로만 준다. 미리보기 레이어를 키우는 식으로 흉내 내면
//  화면에서 겨눈 자리와 찍혀 나온 사진이 서로 다른 배율을 갖게 되어, 오려 내는
//  셈(StickerMaker)이 엉뚱한 데를 자른다. 기기에 걸어 두면 미리보기와 사진이 같은
//  화각을 보므로 그쪽 셈은 한 줄도 손대지 않는다.
//
//  세션은 sessionQueue에서만 만진다. 카메라 설정은 메인 스레드에서 하면 화면이 몇 십
//  밀리초씩 멎는데, 그 멎음이 셔터를 누르는 순간에 겹치면 손이 흔들린 것처럼 느껴진다.
//

@preconcurrency import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class StickerCamera: NSObject, ObservableObject {

    @Published var isAuthorized = false
    /// 실제로 거절당했을 때만 참이 된다. 아직 묻지 않은 상태와 갈라야
    /// '설정에서 켜 주세요'를 엉뚱한 때에 띄우지 않는다.
    @Published var permissionDenied = false
    /// 방금 찍은 한 장 (자르기 전의 온전한 사진)
    @Published var captured: UIImage?
    @Published var position: AVCaptureDevice.Position = .back

    /// 지금 배율 — 사람이 읽는 값이다. 1이 기본 화각, 0.5면 그보다 넓게.
    ///
    /// 기기가 쓰는 videoZoomFactor를 그대로 내보이지 않는 까닭이 있다. 초광각이 딸린
    /// 기기에서는 videoZoomFactor 1이 초광각(사람 눈으로는 0.5배)이라, 그 값을 그대로
    /// 보여 주면 카메라 앱에서 1배로 보이던 화각이 여기서는 2배로 적힌다. 기준이 되는
    /// 배수(baseZoomFactor)로 나눠, 화면에는 어디서나 같은 뜻의 숫자만 세운다.
    @Published private(set) var zoom: CGFloat = 1
    /// 이 기기에서 줄 수 있는 배율의 끝과 끝 (사람이 읽는 값).
    @Published private(set) var zoomRange: ClosedRange<CGFloat> = 1...1
    /// 단추로 내걸 배율들. 기기가 못 주는 값은 빼고 세운다.
    @Published private(set) var zoomStops: [CGFloat] = [1]

    /// 배율을 바꿀 수 있는 기기인지. 못 바꾸면 단추도 집게질도 내걸지 않는다.
    var canZoom: Bool { zoomRange.lowerBound < zoomRange.upperBound }

    /// 앞면 카메라인지. 오려 낼 때 좌우를 되돌려야 해서 바깥에서 묻는다.
    var isMirrored: Bool { position == .front }

    nonisolated let session = AVCaptureSession()
    private nonisolated let photoOutput = AVCapturePhotoOutput()
    private nonisolated let sessionQueue = DispatchQueue(label: "footprint.sticker.camera")
    private nonisolated(unsafe) var currentInput: AVCaptureDeviceInput?
    /// 사람이 말하는 1배가 기기에서는 몇 배인지. (초광각이 딸린 기기에서는 2)
    private nonisolated(unsafe) var baseZoomFactor: CGFloat = 1

    /// 손가락으로 늘릴 수 있는 위쪽 끝 (사람이 읽는 값).
    ///
    /// 기기가 내주는 상한은 100배를 넘기도 하는데, 그 끝은 픽셀을 늘려 놓은 것이라
    /// 무엇을 찍었는지 알아볼 수 없는 얼룩이 된다. 심볼은 알아보라고 만드는 것이니
    /// 알아볼 수 있는 데까지만 연다.
    private nonisolated static let zoomCeiling: CGFloat = 6

    // MARK: - 권한

    func requestAccess() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            permissionDenied = false
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isAuthorized = granted
            permissionDenied = !granted
        default:
            isAuthorized = false
            permissionDenied = true
        }
        if isAuthorized { configure(position: position) }
    }

    // MARK: - 세션

    private nonisolated func configure(position: AVCaptureDevice.Position) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            self.attachInput(for: position)
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                self.photoOutput.maxPhotoQualityPrioritization = .quality
            }
            self.session.commitConfiguration()
            self.configurePhotoConnection()
            self.measureZoom()
            self.session.startRunning()
        }
    }

    private nonisolated func attachInput(for position: AVCaptureDevice.Position) {
        if let currentInput { session.removeInput(currentInput) }
        guard let device = bestDevice(for: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        currentInput = input
    }

    // MARK: - 배율

    /// 붙인 기기에 맞춰 배율의 기준과 끝을 다시 잰다.
    ///
    /// 세션 설정을 마친(commitConfiguration) 뒤에 부른다. 그 전에는 화질 규격이 아직
    /// 확정되지 않아, 재 놓은 상한이 실제로 갈 수 있는 자리와 어긋날 수 있다.
    ///
    /// 기기마다 다르다. 초광각·광각이 한 몸인 기기에서는 videoZoomFactor 1이 초광각이고,
    /// 광각·망원이 한 몸인 기기에서는 1이 광각이다. constituentDevices에서 광각이 몇
    /// 번째인지 찾아 그 자리의 배수를 기준으로 삼으면, 어느 기기에서든 화면에 적히는
    /// 1배가 같은 화각을 가리킨다.
    private nonisolated func measureZoom() {
        guard let device = currentInput?.device else { return }
        let base: CGFloat
        if let index = device.constituentDevices.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }) {
            base = index == 0
                ? 1
                : CGFloat(truncating: device.virtualDeviceSwitchOverVideoZoomFactors[index - 1])
        } else {
            base = 1
        }
        baseZoomFactor = base

        let lower = device.minAvailableVideoZoomFactor / base
        let upper = min(device.maxAvailableVideoZoomFactor / base, Self.zoomCeiling)
        let range = lower...max(lower, upper)

        // 갈 수 있는 데까지만 단추로 세운다. 초광각이 없는 기기에 0.5배 단추를 걸어 두면
        // 눌러도 아무 일이 없는 단추가 된다.
        let stops = [0.5, 1, 2, 3].filter { range.contains($0) }

        // 기기를 갈아 끼울 때마다 배율은 1배로 되돌린다. 앞뒤 카메라가 줄 수 있는 폭이
        // 서로 달라, 뒤에서 쓰던 3배를 앞으로 들고 가면 갈 수 없는 자리를 가리킨다.
        // 잠그지 않고 videoZoomFactor를 건드리면 그 자리에서 앱이 죽는다.
        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = min(max(base, device.minAvailableVideoZoomFactor),
                                         device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        }
        Task { @MainActor in
            self.zoomRange = range
            self.zoomStops = stops.isEmpty ? [1] : stops
            self.zoom = 1
        }
    }

    /// 배율을 준 값으로 옮긴다 (사람이 읽는 값). 기기가 못 가는 자리는 끝으로 붙인다.
    func setZoom(_ value: CGFloat) {
        let clamped = min(max(value, zoomRange.lowerBound), zoomRange.upperBound)
        guard clamped != zoom else { return }
        zoom = clamped
        applyZoom(clamped)
    }

    private nonisolated func applyZoom(_ value: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentInput?.device else { return }
            // 잠그지 못하면 그냥 둔다. 다른 데서 만지는 중이라는 뜻이고, 손가락을 다시
            // 움직이면 어차피 곧 또 부른다.
            guard (try? device.lockForConfiguration()) != nil else { return }
            let factor = value * self.baseZoomFactor
            device.videoZoomFactor = min(max(factor, device.minAvailableVideoZoomFactor),
                                         device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        }
    }

    private nonisolated func bestDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: position) {
                return device
            }
        }
        return AVCaptureDevice.default(for: .video)
    }

    func flip() {
        position = (position == .back) ? .front : .back
        let next = position
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.attachInput(for: next)
            self.session.commitConfiguration()
            self.configurePhotoConnection()
            self.measureZoom()
        }
    }

    /// 세로로 세우고 좌우를 되돌리지 않는다.
    ///
    /// 앞면 카메라의 좌우 뒤집기를 여기서 하지 않는 까닭이 있다. 여기서 뒤집으면 화면에
    /// 보이는 것과 찍혀 나온 것이 서로 다른 좌표계를 갖게 되어, 창 안에서 겨눈 자리를
    /// 사진에서 되찾을 수 없다. 뒤집는 일은 오려 낼 때 한 번만 한다 (StickerMaker).
    private nonisolated func configurePhotoConnection() {
        guard let connection = photoOutput.connection(with: .video) else { return }
        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        if let format = currentInput?.device.activeFormat,
           let best = format.supportedMaxPhotoDimensions.last {
            photoOutput.maxPhotoDimensions = best
        }
    }

    // MARK: - 찍기

    func capture() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            settings.photoQualityPrioritization = .balanced
            settings.flashMode = .off
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// 화면을 떠나면 세션을 멈춘다. 켜 둔 채로 두면 초록 불이 계속 켜져 있고,
    /// 무엇보다 지도를 보는 동안 배터리를 쓴다.
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }
}

extension StickerCamera: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        Task { @MainActor in self.captured = image }
    }
}

// MARK: - 미리보기

/// AVCaptureVideoPreviewLayer를 스위프트UI에 얹는다.
///
/// resizeAspectFill이어야 한다. 오려 내는 셈(StickerMaker)이 aspect-fill을 되짚는
/// 식으로 되어 있어서, 여기만 다른 방식으로 채우면 창에서 겨눈 자리와 잘려 나온 자리가
/// 어긋난다.
struct StickerCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
