//
//  WalkExport.swift
//  FootprintDiary
//
//  걸음 기록을 파일로 내보낸다 — GPX(걸은 길 + 찍은 도장)와 CSV(받은 위치 점 하나하나).
//
//  어느 칸이든 무료다. 내가 걸어 만든 기록을 이 앱 밖으로 가져갈 길은 값을 받고 여는 것이 아니다.
//  GPX 는 다른 지도 · 운동 앱이 그대로 읽는 형식이고, CSV 는 표 계산 앱에서 열린다.
//
//  점이 수십만 개여도 화면이 멈추지 않게, 저장소를 따로 열어 뒤에서 쓴다.
//

import SwiftUI
import SwiftData

enum WalkExport {
    enum Format: String, CaseIterable, Identifiable {
        case gpx, csv
        var id: String { rawValue }

        var title: String {
            switch self {
            case .gpx: String(localized: "GPX로 내보내기")
            case .csv: String(localized: "CSV로 내보내기")
            }
        }

        var symbol: String {
            switch self {
            case .gpx: "point.topleft.down.to.point.bottomright.curvepath"
            case .csv: "tablecells"
            }
        }
    }

    /// 파일을 임시 폴더에 쓰고 그 주소를 돌려준다.
    static func write(_ format: Format, container: ModelContainer) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let track = try context.fetch(FetchDescriptor<TrackPoint>(sortBy: [SortDescriptor(\.timestamp)]))
            let text: String
            switch format {
            case .gpx:
                let stamps = try context.fetch(FetchDescriptor<MapStamp>(sortBy: [SortDescriptor(\.createdAt)]))
                text = gpx(track: track, stamps: stamps)
            case .csv:
                text = csv(track: track)
            }
            let day = Date.now.formatted(.iso8601.year().month().day())
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("FootprintDiary-\(day).\(format.rawValue)")
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        }.value
    }

    // MARK: - GPX

    /// 하루를 한 구간(trkseg)으로, 찍은 도장은 지점(wpt)으로.
    static func gpx(track: [TrackPoint], stamps: [MapStamp], calendar: Calendar = .current) -> String {
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="FootprintDiary" xmlns="http://www.topografix.com/GPX/1/1">

        """
        for stamp in stamps {
            out += "  <wpt lat=\"\(stamp.latitude)\" lon=\"\(stamp.longitude)\">"
            out += "<time>\(time(stamp.createdAt))</time><name>\(escaped(stamp.displayName))</name>"
            if !stamp.note.isEmpty { out += "<desc>\(escaped(stamp.note))</desc>" }
            out += "</wpt>\n"
        }
        out += "  <trk><name>FootprintDiary</name>\n"
        let days = Dictionary(grouping: track) { calendar.startOfDay(for: $0.timestamp) }
        for day in days.keys.sorted() {
            out += "    <trkseg>\n"
            for point in days[day] ?? [] {
                out += "      <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"><time>\(time(point.timestamp))</time></trkpt>\n"
            }
            out += "    </trkseg>\n"
        }
        out += "  </trk>\n</gpx>\n"
        return out
    }

    // MARK: - CSV

    static func csv(track: [TrackPoint]) -> String {
        var out = "timestamp,latitude,longitude,speed_mps,horizontal_accuracy_m\n"
        for point in track {
            out += "\(time(point.timestamp)),\(point.latitude),\(point.longitude),"
            out += "\(point.speed >= 0 ? String(point.speed) : ""),"
            out += "\(point.horizontalAccuracy >= 0 ? String(point.horizontalAccuracy) : "")\n"
        }
        return out
    }

    // MARK: -

    private static func time(_ date: Date) -> String { date.formatted(.iso8601) }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - 설정의 한 칸

/// 설정 ▸ 내 기록 내보내기. 고른 형식으로 파일을 만들어 공유 시트에 넘긴다.
struct WalkExportSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var working: WalkExport.Format?
    @State private var file: ExportedFile?
    @State private var failure: String?

    private struct ExportedFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        Section {
            ForEach(WalkExport.Format.allCases) { format in
                Button {
                    export(format)
                } label: {
                    HStack {
                        Label(format.title, systemImage: format.symbol)
                        Spacer()
                        if working == format { ProgressView() }
                    }
                }
                .foregroundStyle(.primary)
                .disabled(working != nil)
            }
        } header: {
            Text("내 기록 내보내기")
        } footer: {
            Text("GPX는 걸은 길과 찍은 도장을 다른 지도 앱에서 열어요. CSV는 받은 위치를 표로 담아요.")
        }
        .sheet(item: $file) { file in
            ShareSheet(items: [file.url])
        }
        .alert("파일을 만들지 못했어요",
               isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func export(_ format: WalkExport.Format) {
        working = format
        let container = modelContext.container
        Task {
            do {
                file = ExportedFile(url: try await WalkExport.write(format, container: container))
            } catch {
                failure = error.localizedDescription
            }
            working = nil
        }
    }
}
