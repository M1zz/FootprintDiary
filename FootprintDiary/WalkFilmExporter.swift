//
//  WalkFilmExporter.swift
//  FootprintDiary
//
//  필름을 한 칸씩 그려 영상 파일로 굽는다.
//
//  화면 녹화가 아니라 한 칸씩 직접 그린다. 그래야 기기가 느리든 빠르든 결과가 같고,
//  화면에 없는 크기(1080×1920)로도 뽑을 수 있다. 그리는 법은 WalkFilm 한 벌만 쓰므로
//  미리 본 것과 나가는 것이 어긋나지 않는다.
//

import Foundation
import AVFoundation
import MapKit
import UIKit

enum WalkFilmExporter {

    /// 내보낼 영상의 크기. 세로로 긴 화면에 그대로 올릴 수 있는 비율이다.
    static let size = CGSize(width: 1_080, height: 1_920)
    static let framesPerSecond: Int32 = 30
    /// 필름 한 편의 길이(초)
    static let duration: TimeInterval = 12
    /// 다 그린 뒤 마지막 그림을 이만큼(초) 붙들어 둔다.
    /// 마지막 칸에서 곧바로 끊기면 완성된 지도를 볼 틈이 없다.
    static let holdAtEnd: TimeInterval = 1.6

    enum ExportError: LocalizedError {
        case nothingToDraw
        case cannotWrite

        var errorDescription: String? {
            switch self {
            case .nothingToDraw: return "이 기간에는 그릴 발자국이 없어요."
            case .cannotWrite: return "영상을 만들지 못했어요. 저장 공간을 확인해주세요."
            }
        }
    }

    /// 필름을 mp4로 굽는다. 만들어진 파일의 자리를 돌려준다.
    /// - Parameter onProgress: 0에서 1까지, 얼마나 구웠는지 (메인에서 불린다)
    static func export(
        reel: WalkFilm.Reel,
        terrain: TerrainMask?,
        palette: WalkFilm.Palette,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        guard !reel.isEmpty else { throw ExportError.nothingToDraw }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("내지도-\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            throw ExportError.cannotWrite
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )

        guard writer.canAdd(input) else { throw ExportError.cannotWrite }
        writer.add(input)
        guard writer.startWriting() else { throw ExportError.cannotWrite }
        writer.startSession(atSourceTime: .zero)

        let drawnFrames = Int(duration * Double(framesPerSecond))
        let heldFrames = Int(holdAtEnd * Double(framesPerSecond))
        let totalFrames = drawnFrames + heldFrames

        for frame in 0..<totalFrames {
            // 다 그린 뒤에는 마지막 그림을 그대로 붙들어 둔다
            let progress = frame < drawnFrames
                ? Double(frame) / Double(max(drawnFrames - 1, 1))
                : 1

            try await waitUntilReady(input)

            guard let pool = adaptor.pixelBufferPool,
                  let buffer = pixelBuffer(from: pool, drawing: { context in
                      WalkFilm.draw(
                          reel,
                          terrain: terrain,
                          palette: palette,
                          progress: progress,
                          in: context,
                          size: size
                      )
                      drawCaption(WalkFilm.caption(reel, progress: progress), palette: palette, in: context)
                  })
            else {
                writer.cancelWriting()
                throw ExportError.cannotWrite
            }

            let time = CMTime(value: CMTimeValue(frame), timescale: framesPerSecond)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                writer.cancelWriting()
                throw ExportError.cannotWrite
            }

            let done = Double(frame + 1) / Double(totalFrames)
            await MainActor.run { onProgress(done) }
        }

        input.markAsFinished()
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw ExportError.cannotWrite
        }
        return url
    }

    // MARK: - 한 칸 굽기

    /// 쓸 준비가 될 때까지 기다린다. 붙들고 있으면 쓰기가 막히므로 조금씩 양보한다.
    private static func waitUntilReady(_ input: AVAssetWriterInput) async throws {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private static func pixelBuffer(
        from pool: CVPixelBufferPool,
        drawing: (CGContext) -> Void
    ) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // 왼쪽 위를 원점으로 삼는다 (WalkFilm이 쓰는 방향과 맞춘다)
        context.translateBy(x: 0, y: CGFloat(CVPixelBufferGetHeight(buffer)))
        context.scaleBy(x: 1, y: -1)

        UIGraphicsPushContext(context)
        drawing(context)
        UIGraphicsPopContext()
        return buffer
    }

    /// 지금 어느 날인지 아래에 적어 둔다. 날짜가 없으면 그냥 점이 늘어나는 그림일 뿐이다.
    private static func drawCaption(_ text: String, palette: WalkFilm.Palette, in context: CGContext) {
        guard !text.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 46, weight: .semibold),
            .foregroundColor: palette.ink.withAlphaComponent(0.75)
        ]
        let line = NSAttributedString(string: text, attributes: attributes)
        let bounds = line.size()
        line.draw(at: CGPoint(
            x: (size.width - bounds.width) / 2,
            y: size.height - bounds.height - 96
        ))
    }
}
