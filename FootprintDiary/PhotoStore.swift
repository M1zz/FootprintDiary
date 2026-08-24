//
//  PhotoStore.swift
//  FootprintDiary
//
//  사진을 저장 크기로 줄이고, 그 날 일기에 붙이는 공통 처리.
//  일기 화면과 스팟 촬영이 같은 규칙을 쓰도록 한곳에 모아 둔다.
//

import UIKit
import SwiftData

enum PhotoStore {

    /// 저장할 사진의 긴 변 최대 길이
    static let maxDimension: CGFloat = 1600

    /// 원본(수 MB~수십 MB)을 그대로 저장하지 않고 화면 표시에 충분한 크기로 줄인다
    static func downscaledJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longSide = max(image.size.width, image.size.height)
        guard longSide > maxDimension else { return data }
        return jpegData(from: image)
    }

    static func jpegData(from image: UIImage) -> Data? {
        let longSide = max(image.size.width, image.size.height)
        guard longSide > maxDimension else { return image.jpegData(compressionQuality: 0.85) }

        let scale = maxDimension / longSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }

    /// 해당 날짜의 일기를 가져오거나 새로 만든다
    @MainActor
    static func entry(for day: Date, context: ModelContext) -> DiaryEntry {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let descriptor = FetchDescriptor<DiaryEntry>(
            predicate: #Predicate<DiaryEntry> { $0.dayStart >= dayStart && $0.dayStart < dayEnd }
        )
        if let existing = (try? context.fetch(descriptor))?.first { return existing }

        let created = DiaryEntry(dayStart: dayStart)
        context.insert(created)
        return created
    }

    /// 사진을 그 날 일기에 붙인다 (저장은 호출한 쪽에서 한다)
    @MainActor
    static func attachToDiary(data: Data, on day: Date, context: ModelContext) {
        let entry = entry(for: day, context: context)
        entry.addPhoto(DiaryPhoto(data: data))
        entry.updatedAt = .now
    }
}
