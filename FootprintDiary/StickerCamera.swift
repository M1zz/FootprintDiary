//
//  StickerCamera.swift
//  FootprintDiary
//
//  스티커를 찍는 카메라 — 미리보기와 한 장 찍기.
//
//  StampCamera(펀칭) 앱에서 가져와 이 앱에 필요한 만큼만 남겼다. 저쪽에는 줌 단계와
//  '움직이는 우표'(연속 프레임)가 있는데, 여기서 만드는 것은 지도에 얹을 손톱만 한
//  심볼 하나다. 30pt짜리 그림에 줌 배율과 움직임은 아무 뜻이 없고, 그것들을 데려오면
//  화면이 카메라 앱 흉내를 내기 시작한다. 이 화면이 할 일은 하나뿐이다 — 눈앞의 것을
//  창 안에 넣고 한 번 누르는 것.
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

    /// 앞면 카메라인지. 오려 낼 때 좌우를 되돌려야 해서 바깥에서 묻는다.
    var isMirrored: Bool { position == .front }

    nonisolated let session = AVCaptureSession()
    private nonisolated let photoOutput = AVCapturePhotoOutput()
    private nonisolated let sessionQueue = DispatchQueue(label: "footprint.sticker.camera")
    private nonisolated(unsafe) var currentInput: AVCaptureDeviceInput?

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
