//
//  DemoSeed.swift
//  FootprintDiary
//
//  스토어 스크린샷용 가상 기록. DEBUG 빌드에서 `-demoSeed` 로 켰을 때만 쓰인다.
//  배포(Release) 빌드에는 들어가지 않는다.
//
//  - 저장소는 메모리에만 두어 진짜 기록과 섞이지 않는다 (아이클라우드도 붙이지 않는다).
//  - 두 달 남짓의 산책을 바둑판 골목 위에 같은 씨앗으로 그려, 언어마다 같은 그림이 나온다.
//  - 자리 이름처럼 사람이 붙인 글은 그 언어로 넣는다 (`DemoSeed.names`).
//  - `-demoScreen compass|stamps|diary` 로 그 화면을 열어 둔 채 시작한다.
//    달력은 `-footprint.diaryLayout 달력` 을 함께 넘긴다.
//

#if DEBUG
import Foundation
import SwiftData
import CoreLocation
import TipKit

enum DemoSeed {

    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demoSeed") }

    /// `-demoScreen <이름>` 의 값
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// 지도 한가운데 (시뮬레이터 위치도 여기에 둔다)
    static let center = CLLocationCoordinate2D(latitude: 37.5563, longitude: 126.9236)

    /// 첫 화면을 바로 지도로 — 안내·새로 생긴 것·팁을 건너뛴다
    static func prepareDefaults() {
        UserDefaults.standard.set(true, forKey: "footprint.hasOnboarded")
        WhatsNew.markSeen()
        Tips.hideAllTipsForTesting()
    }

    // MARK: - 사람이 붙인 이름 (언어마다)

    private struct Names {
        let bakery: String
        let cafe: String
        let tree: String
        let cat: String
    }

    private static let names: [String: Names] = [
        "ko": Names(bakery: "소금빵 맛집", cafe: "퇴근길 카페", tree: "은행나무", cat: "치즈 고양이"),
        "en": Names(bakery: "Best croissants", cafe: "After-work café", tree: "Old ginkgo", cat: "Ginger the cat"),
        "ja": Names(bakery: "塩パンの店", cafe: "帰り道カフェ", tree: "イチョウの木", cat: "茶トラ猫"),
        "zh-Hans": Names(bakery: "好吃的面包店", cafe: "下班路上的咖啡馆", tree: "银杏树", cat: "橘猫"),
        "zh-Hant": Names(bakery: "好吃的麵包店", cafe: "下班路上的咖啡店", tree: "銀杏樹", cat: "橘貓"),
        "es": Names(bakery: "Panadería favorita", cafe: "Café de la vuelta", tree: "Ginkgo viejo", cat: "Gato naranja"),
        "de": Names(bakery: "Lieblingsbäcker", cafe: "Feierabend-Café", tree: "Alter Ginkgo", cat: "Roter Kater"),
        "fr": Names(bakery: "Ma boulangerie", cafe: "Café du retour", tree: "Vieux ginkgo", cat: "Chat roux"),
        "it": Names(bakery: "Forno preferito", cafe: "Bar del ritorno", tree: "Vecchio ginkgo", cat: "Gatto rosso"),
        "pt-BR": Names(bakery: "Padaria favorita", cafe: "Café da volta", tree: "Ginkgo antigo", cat: "Gato laranja"),
        "ru": Names(bakery: "Любимая пекарня", cafe: "Кофейня по пути", tree: "Старое гинкго", cat: "Рыжий кот"),
        "th": Names(bakery: "ร้านขนมปังเจ้าประจำ", cafe: "คาเฟ่ทางกลับบ้าน", tree: "ต้นแปะก๊วย", cat: "แมวส้ม"),
        "vi": Names(bakery: "Tiệm bánh quen", cafe: "Quán cà phê tan làm", tree: "Cây bạch quả", cat: "Mèo cam"),
        "cs": Names(bakery: "Oblíbená pekárna", cafe: "Kavárna po práci", tree: "Starý jinan", cat: "Zrzavý kocour"),
        "da": Names(bakery: "Yndlingsbageren", cafe: "Café på vej hjem", tree: "Gammel ginkgo", cat: "Rød kat"),
        "el": Names(bakery: "Ο φούρνος μου", cafe: "Καφέ της επιστροφής", tree: "Παλιό τζίνκο", cat: "Πορτοκαλί γάτα"),
        "fi": Names(bakery: "Lempileipomo", cafe: "Kotimatkan kahvila", tree: "Vanha neidonhius", cat: "Oranssi kissa"),
        "id": Names(bakery: "Toko roti favorit", cafe: "Kafe pulang kerja", tree: "Pohon ginkgo", cat: "Kucing oranye"),
        "nb": Names(bakery: "Favorittbakeren", cafe: "Kafé på vei hjem", tree: "Gammel ginkgo", cat: "Rød katt"),
        "nl": Names(bakery: "Favoriete bakker", cafe: "Café op weg naar huis", tree: "Oude ginkgo", cat: "Rode kater"),
        "pl": Names(bakery: "Ulubiona piekarnia", cafe: "Kawiarnia po pracy", tree: "Stary miłorząb", cat: "Rudy kot"),
        "sv": Names(bakery: "Favoritbageriet", cafe: "Kafé på väg hem", tree: "Gammal ginkgo", cat: "Röd katt"),
        "tr": Names(bakery: "Favori fırın", cafe: "İş çıkışı kafesi", tree: "Yaşlı ginkgo", cat: "Sarman kedi"),
    ]

    private static var localNames: Names {
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        if preferred == "en-GB" {
            return Names(bakery: "Best croissants", cafe: "After-work café", tree: "Old ginkgo", cat: "Ginger the cat")
        }
        return names[preferred] ?? names["en"]!
    }

    // MARK: - 씨 뿌리기

    /// 메모리 저장소를 만들어 가상 기록을 채운다
    static func makeContainer(schema: Schema) -> ModelContainer {
        let container = try! ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        seed(into: context)
        try? context.save()
        return container
    }

    /// 같은 씨앗이면 같은 수가 나오는 난수 (언어마다 같은 그림을 위해)
    private struct Rng {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
        mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    }

    private static let block: Double = 85        // 골목 한 칸(m)
    private static let pointStep: Double = 8      // 점 사이(m)

    private static func coordinate(x: Double, y: Double) -> CLLocationCoordinate2D {
        let lat = center.latitude + y / 111_320
        let lon = center.longitude + x / (111_320 * cos(center.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func seed(into context: ModelContext) {
        var rng = Rng(state: 20_261_008)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let directions = [(1, 0), (0, 1), (-1, 0), (0, -1)]

        /// 한 번의 산책: 집 근처에서 시작해 바둑판을 따라 걷는다
        func walk(dayOffset: Int, hour: Int, minute: Int, segments: Int, bias: (Int, Int)?) {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today),
                  var time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return }
            var gx = rng.int(5) - 2, gy = rng.int(5) - 2
            var dir = directions[rng.int(4)]
            for _ in 0..<segments {
                if rng.int(2) == 0 { dir = directions[rng.int(4)] }
                if let bias, rng.int(3) == 0 { dir = bias }
                // 너무 멀리 가면 집 쪽으로 돌린다
                if abs(gx + dir.0) > 9 || abs(gy + dir.1) > 8 { dir = (-dir.0, -dir.1) }
                let steps = Int(block / pointStep)
                for s in 0..<steps {
                    let x = (Double(gx) + Double(dir.0) * Double(s) / Double(steps)) * block
                    let y = (Double(gy) + Double(dir.1) * Double(s) / Double(steps)) * block
                    let c = coordinate(x: x, y: y)
                    context.insert(TrackPoint(timestamp: time, latitude: c.latitude, longitude: c.longitude,
                                              speed: 1.3, horizontalAccuracy: 5))
                    time = time.addingTimeInterval(pointStep / 1.3)
                }
                gx += dir.0; gy += dir.1
            }
        }

        // 지난 두 달: 거의 날마다, 아침이나 저녁에
        for offset in stride(from: 62, through: 1, by: -1) where rng.int(10) < 8 {
            let morning = rng.int(2) == 0
            walk(dayOffset: offset, hour: morning ? 8 : 18, minute: morning ? 0 : 30,
                 segments: 18 + rng.int(14), bias: nil)
        }
        // 오늘: 동쪽 끝으로 처음 가 보는 길
        walk(dayOffset: 0, hour: 8, minute: 0, segments: 24, bias: (1, 0))

        // 도장
        let n = localNames
        func stamp(_ id: String, _ x: Double, _ y: Double, daysAgo: Int, name: String = "", planned: Bool = false) {
            let created = calendar.date(byAdding: .day, value: -daysAgo, to: today)!.addingTimeInterval(9 * 3600)
            let s = MapStamp(kind: StampCatalog.kind(id: id), coordinate: coordinate(x: x * block, y: y * block),
                             createdAt: created, placeName: name, isPlanned: planned)
            context.insert(s)
        }
        stamp("home", 0, 0, daysAgo: 60)
        stamp("bakery", -3, 1, daysAgo: 40, name: n.bakery)
        stamp("cafe", 2, 0.5, daysAgo: 30, name: n.cafe)
        stamp("big_tree", 3, -2.5, daysAgo: 25, name: n.tree)
        stamp("cat", -0.5, -3, daysAgo: 20, name: n.cat)
        stamp("bench", 0.5, 3, daysAgo: 14)
        stamp("museum", 4, 3.5, daysAgo: 10)
        stamp("library", -4.5, -3.5, daysAgo: 7)
        stamp("stream", 6, -4.5, daysAgo: 15, planned: true)
        stamp("hill_view", -7, 4, daysAgo: 15, planned: true)
    }
}
#endif
