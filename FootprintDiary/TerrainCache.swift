//
//  TerrainCache.swift
//  FootprintDiary
//
//  한 번 뜬 물과 산의 본을 기기에 적어 둔다.
//
//  본을 뜨려면 지도를 한 장 찍고 화소를 수십만 개 훑어야 한다. 그래서 앱을 열 때마다
//  종이가 한참 비어 있다가 물과 산, 나무가 뒤늦게 돋았다. 그런데 사람은 대개 늘 걷던
//  동네를 다시 연다. 강과 산은 그사이 옮겨 가지 않는다 — 한 번 뜬 본은 다시 써도 된다.
//
//  그래서 뜬 본을 Caches 폴더에 그림 파일로 남기고, 같은 자리를 다시 보면 찍지 않고 읽어 온다.
//  나무와 봉우리 자리는 본과 칸 번호에서만 나오므로(MapGrid) 본만 같으면 늘 같은 자리에 선다.
//
//  지도는 가끔 바뀌므로(새 매립지, 고친 물길) 한 달이 지나면 다시 뜬다. 기기가 자리가 모자라면
//  Caches는 시스템이 비울 수 있는데, 그러면 처음처럼 다시 뜰 뿐이다.
//

import Foundation
import ImageIO
import MapKit
import UniformTypeIdentifiers

final class TerrainCache {
    static let shared = TerrainCache()

    /// 본 뜨는 법을 바꾸면 올린다. 옛 법으로 뜬 본은 버린다.
    /// 2: 물빛 범위를 좁히고 작은 호수를 지우지 않게 했다
    static let formatVersion = 2
    /// 적어 두는 본의 수. 넘으면 오래 안 본 것부터 지운다. 바둑판 조각마다 하나씩 적으므로 넉넉히 둔다.
    static let maxEntries = 300
    /// 이보다 오래된 본은 다시 뜬다
    static let lifetime: TimeInterval = 30 * 24 * 60 * 60
    /// 적어 둔 본이 지금 보려는 범위보다 이만큼 넘게 넓으면 성겨 보이므로 쓰지 않는다.
    /// 지도 화면이 '이만큼 확대해 들어가면 다시 뜬다'고 정한 문턱(0.4)과 맞춘다.
    static let maxCoarseness = 2.5
    /// 읽어 둔 본을 메모리에도 이만큼 들고 있는다 (오가며 볼 때 파일도 안 읽게)
    static let memoryLimit = 4

    private struct Rect: Codable {
        let x, y, width, height: Double

        init(_ rect: MKMapRect) {
            x = rect.origin.x
            y = rect.origin.y
            width = rect.size.width
            height = rect.size.height
        }

        var mapRect: MKMapRect { MKMapRect(x: x, y: y, width: width, height: height) }
    }

    private struct Entry: Codable {
        let id: String
        let waterRect: Rect
        let hillRect: Rect
        /// 물도 산도 없던 자리
        let isBare: Bool
        let savedAt: Date
        var usedAt: Date
    }

    private struct Index: Codable {
        var version: Int
        var entries: [Entry]
    }

    private enum Layer: String, CaseIterable {
        case water, hills, shore, core
    }

    /// 파일과 목록은 이 줄에서만 만진다
    private let queue = DispatchQueue(label: "TerrainCache", qos: .userInitiated)
    private let folder: URL
    private var index: Index?
    private var memory: [(id: String, mask: TerrainMask)] = []

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        folder = caches.appendingPathComponent("Terrain", isDirectory: true)
    }

    // MARK: 찾기

    /// 이 범위를 쓸 만큼 덮는 본이 적혀 있으면 돌려준다. 없으면 nil. 뒤쪽 줄에서 부른다.
    ///
    /// 화면은 보이는 자리의 두 배 범위를 달라고 하므로, 그 가운데(실제로 보이는 자리)만 덮으면 쓴다.
    func lookup(_ rect: MKMapRect, then handle: @escaping (TerrainSearch?) -> Void) {
        queue.async {
            handle(self.cached(for: rect))
        }
    }

    private func cached(for rect: MKMapRect) -> TerrainSearch? {
        guard rect.size.width > 0 else { return nil }
        let visible = rect.insetBy(dx: rect.size.width / 4, dy: rect.size.height / 4)
        let now = Date()
        var index = loadIndex()

        // 덮는 것 가운데 가장 촘촘한 것
        let candidates = index.entries.enumerated().filter { _, entry in
            let covered = entry.waterRect.mapRect
            return now.timeIntervalSince(entry.savedAt) < Self.lifetime
                && covered.contains(visible)
                && covered.size.width <= rect.size.width * Self.maxCoarseness
        }
        guard let (position, entry) = candidates.min(by: {
            $0.element.waterRect.width < $1.element.waterRect.width
        }) else { return nil }

        let result: TerrainSearch
        if entry.isBare {
            result = .bare
        } else if let mask = mask(for: entry) {
            result = .found(mask)
        } else {
            // 파일이 사라졌다 (시스템이 Caches를 비웠다) — 목록에서도 지운다
            forget([entry.id], in: &index)
            self.index = index
            saveIndex(index)
            return nil
        }

        index.entries[position].usedAt = now
        self.index = index
        saveIndex(index)
        return result
    }

    private func mask(for entry: Entry) -> TerrainMask? {
        if let held = memory.first(where: { $0.id == entry.id }) { return held.mask }

        func read(_ layer: Layer) -> CGImage? {
            Self.readStencil(at: file(entry.id, layer))
        }
        let water = read(.water)
        let hills = read(.hills)
        // 적을 때 둘 다 없는 본은 적지 않는다. 둘 다 없으면 파일이 사라진 것이다.
        guard water != nil || hills != nil else { return nil }

        let mask = TerrainMask(
            waterRect: entry.waterRect.mapRect,
            water: water,
            hillRect: entry.hillRect.mapRect,
            hills: hills,
            waterShore: read(.shore),
            waterCore: read(.core)
        )
        remember(entry.id, mask)
        return mask
    }

    // MARK: 적기

    /// 새로 뜬 본을 적어 둔다. 찍지 못한 것(.failed)은 적지 않는다 — 다음에 다시 해 봐야 한다.
    func store(_ result: TerrainSearch, for rect: MKMapRect) {
        queue.async {
            let id = UUID().uuidString
            let entry: Entry
            switch result {
            case .failed:
                return
            case .bare:
                entry = Entry(
                    id: id, waterRect: Rect(rect), hillRect: Rect(rect),
                    isBare: true, savedAt: Date(), usedAt: Date()
                )
            case .found(let mask):
                let layers: [(Layer, CGImage?)] = [
                    (.water, mask.water), (.hills, mask.hills),
                    (.shore, mask.waterShore), (.core, mask.waterCore),
                ]
                do {
                    try FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
                    for case let (layer, stencil?) in layers {
                        try Self.writeStencil(stencil, to: self.file(id, layer))
                    }
                } catch {
                    for layer in Layer.allCases { try? FileManager.default.removeItem(at: self.file(id, layer)) }
                    return
                }
                entry = Entry(
                    id: id, waterRect: Rect(mask.waterRect), hillRect: Rect(mask.hillRect),
                    isBare: false, savedAt: Date(), usedAt: Date()
                )
                self.remember(id, mask)
            }

            var index = self.loadIndex()
            // 새 본이 통째로 덮는 옛 본은 쓸 일이 없다
            let covered = entry.waterRect.mapRect
            let outdated = index.entries.filter { old in
                let oldRect = old.waterRect.mapRect
                return covered.contains(oldRect) && oldRect.size.width * Self.maxCoarseness >= covered.size.width
            }
            self.forget(outdated.map(\.id), in: &index)
            index.entries.append(entry)

            // 오래 안 본 것부터 덜어 낸다
            if index.entries.count > Self.maxEntries {
                let surplus = index.entries
                    .sorted { $0.usedAt < $1.usedAt }
                    .prefix(index.entries.count - Self.maxEntries)
                self.forget(surplus.map(\.id), in: &index)
            }
            self.index = index
            self.saveIndex(index)
        }
    }

    private func remember(_ id: String, _ mask: TerrainMask) {
        memory.removeAll { $0.id == id }
        memory.append((id, mask))
        if memory.count > Self.memoryLimit { memory.removeFirst(memory.count - Self.memoryLimit) }
    }

    private func forget(_ ids: [String], in index: inout Index) {
        guard !ids.isEmpty else { return }
        let gone = Set(ids)
        index.entries.removeAll { gone.contains($0.id) }
        memory.removeAll { gone.contains($0.id) }
        for id in ids {
            for layer in Layer.allCases { try? FileManager.default.removeItem(at: file(id, layer)) }
        }
    }

    // MARK: 목록

    private var indexFile: URL { folder.appendingPathComponent("index.json") }

    private func file(_ id: String, _ layer: Layer) -> URL {
        folder.appendingPathComponent("\(id)-\(layer.rawValue).png")
    }

    private func loadIndex() -> Index {
        if let index { return index }
        var loaded = Index(version: Self.formatVersion, entries: [])
        if let data = try? Data(contentsOf: indexFile),
           let decoded = try? JSONDecoder().decode(Index.self, from: data),
           decoded.version == Self.formatVersion {
            loaded = decoded
        } else {
            // 목록이 없거나 옛 법으로 뜬 것이다 — 남은 파일을 모두 걷어 낸다
            try? FileManager.default.removeItem(at: folder)
        }
        index = loaded
        return loaded
    }

    private func saveIndex(_ index: Index) {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: indexFile, options: .atomic)
    }

    // MARK: 본 ↔ 파일

    /// 스텐실(무늬 0, 바깥 255)을 흑백 PNG로 적는다. 덩어리 모양이라 아주 작게 눌린다.
    private static func writeStencil(_ stencil: CGImage, to url: URL) throws {
        guard stencil.bitsPerPixel == 8,
              let provider = stencil.dataProvider,
              let gray = CGImage(
                  width: stencil.width,
                  height: stencil.height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 8,
                  bytesPerRow: stencil.bytesPerRow,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, gray, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// 적어 둔 PNG를 다시 스텐실로 만든다. 없으면 nil.
    private static func readStencil(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let raw = context.data else { return nil }
        // 그림판의 메모리는 그림판이 사라지면 함께 사라지므로 바이트를 옮겨 담는다
        let bytes = Data(bytes: raw, count: context.bytesPerRow * height)
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(
            maskWidth: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: context.bytesPerRow,
            provider: provider,
            decode: nil,
            shouldInterpolate: true
        )
    }
}
