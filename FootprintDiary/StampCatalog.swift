//
//  StampCatalog.swift
//  FootprintDiary
//
//  지도에 찍을 수 있는 스탬프 목록.
//
//  종류가 200가지가 넘어 열거형으로 두면 손대기 어렵다. 그래서 값의 목록으로 두고
//  저장에는 id 문자열만 쓴다. 나중에 항목이 늘거나 빠져도 이미 찍힌 스탬프가 깨지지 않는다.
//
//  심볼 이름은 iOS 17에서 실제로 쓸 수 있는 것만 골랐다 (CoreGlyphs의 도입 버전표로 검증).
//  이름이 틀리면 도장 안이 빈 칸으로 찍히는데 눈으로는 알아채기 어렵다.
//

import Foundation

/// 스탬프 한 종류
struct StampKind: Identifiable, Hashable {
    let id: String
    let title: String
    let symbolName: String
    let group: String
}

enum StampCatalog {

    /// 묶음의 차례 (고르는 화면에 이 순서로 나온다)
    static let groups: [String] = [
        "길",
        "쉼터",
        "자연",
        "동물",
        "가게",
        "먹을 곳",
        "시설",
        "운동·놀이",
        "조심",
        "기억"
    ]

    static let all: [StampKind] = [
        StampKind(id: "shortcut", title: "지름길", symbolName: "arrow.triangle.turn.up.right.diamond.fill", group: "길"),
        StampKind(id: "stairs", title: "계단", symbolName: "figure.stairs", group: "길"),
        StampKind(id: "steep", title: "가파른 오르막", symbolName: "arrow.up.right", group: "길"),
        StampKind(id: "downhill", title: "내리막", symbolName: "arrow.down.right", group: "길"),
        StampKind(id: "dead_end", title: "막다른 길", symbolName: "nosign", group: "길"),
        StampKind(id: "alley", title: "좁은 골목", symbolName: "arrow.triangle.branch", group: "길"),
        StampKind(id: "overpass", title: "육교", symbolName: "arrow.up.and.down.righttriangle.up.righttriangle.down", group: "길"),
        StampKind(id: "underpass", title: "지하도", symbolName: "arrow.down.to.line", group: "길"),
        StampKind(id: "crosswalk", title: "건널목", symbolName: "figure.walk", group: "길"),
        StampKind(id: "bridge", title: "다리", symbolName: "road.lanes", group: "길"),
        StampKind(id: "tunnel", title: "굴다리", symbolName: "circle.righthalf.filled", group: "길"),
        StampKind(id: "trail", title: "산책로", symbolName: "figure.hiking", group: "길"),
        StampKind(id: "deck", title: "데크길", symbolName: "rectangle.split.3x1", group: "길"),
        StampKind(id: "dirt_path", title: "흙길", symbolName: "leaf", group: "길"),
        StampKind(id: "gravel", title: "자갈길", symbolName: "circle.grid.3x3.fill", group: "길"),
        StampKind(id: "wide_road", title: "넓은 인도", symbolName: "road.lanes.curved.right", group: "길"),
        StampKind(id: "no_sidewalk", title: "인도 없음", symbolName: "exclamationmark.triangle", group: "길"),
        StampKind(id: "through_building", title: "건물 관통로", symbolName: "building.2", group: "길"),
        StampKind(id: "park_path", title: "공원 샛길", symbolName: "tree", group: "길"),
        StampKind(id: "riverside", title: "하천길", symbolName: "water.waves", group: "길"),
        StampKind(id: "ramp", title: "경사로", symbolName: "arrow.up.forward", group: "길"),
        StampKind(id: "loop", title: "한 바퀴 돌기 좋음", symbolName: "arrow.triangle.capsulepath", group: "길"),
        StampKind(id: "bench", title: "벤치", symbolName: "chair.lounge.fill", group: "쉼터"),
        StampKind(id: "pavilion", title: "정자", symbolName: "house.lodge", group: "쉼터"),
        StampKind(id: "shade", title: "그늘", symbolName: "tree.fill", group: "쉼터"),
        StampKind(id: "lawn", title: "잔디밭", symbolName: "leaf.fill", group: "쉼터"),
        StampKind(id: "rest_area", title: "쉼터", symbolName: "figure.seated.side", group: "쉼터"),
        StampKind(id: "restroom", title: "화장실", symbolName: "toilet.fill", group: "쉼터"),
        StampKind(id: "water_fountain", title: "음수대", symbolName: "drop.fill", group: "쉼터"),
        StampKind(id: "shelter", title: "비 피할 곳", symbolName: "umbrella.fill", group: "쉼터"),
        StampKind(id: "sunny_spot", title: "햇볕 드는 자리", symbolName: "sun.max.fill", group: "쉼터"),
        StampKind(id: "wind", title: "바람 시원한 곳", symbolName: "wind", group: "쉼터"),
        StampKind(id: "quiet", title: "조용한 곳", symbolName: "speaker.slash.fill", group: "쉼터"),
        StampKind(id: "table", title: "앉아 먹을 자리", symbolName: "table.furniture", group: "쉼터"),
        StampKind(id: "shoe_rest", title: "신발 털 곳", symbolName: "shoe", group: "쉼터"),
        StampKind(id: "smoking", title: "흡연구역", symbolName: "smoke.fill", group: "쉼터"),
        StampKind(id: "no_smoking", title: "금연", symbolName: "smoke", group: "쉼터"),
        StampKind(id: "wifi", title: "와이파이 되는 곳", symbolName: "wifi", group: "쉼터"),
        StampKind(id: "charging", title: "충전할 곳", symbolName: "bolt.fill", group: "쉼터"),
        StampKind(id: "locker", title: "물품보관함", symbolName: "lock.square.fill", group: "쉼터"),
        StampKind(id: "big_tree", title: "큰 나무", symbolName: "tree.fill", group: "자연"),
        StampKind(id: "cherry", title: "벚나무", symbolName: "camera.macro", group: "자연"),
        StampKind(id: "ginkgo", title: "은행나무", symbolName: "leaf.circle.fill", group: "자연"),
        StampKind(id: "maple", title: "단풍", symbolName: "flame.fill", group: "자연"),
        StampKind(id: "flowers", title: "꽃밭", symbolName: "camera.macro.circle.fill", group: "자연"),
        StampKind(id: "stream", title: "개천", symbolName: "water.waves", group: "자연"),
        StampKind(id: "pond", title: "연못", symbolName: "drop.circle.fill", group: "자연"),
        StampKind(id: "fountain", title: "분수", symbolName: "drop.triangle.fill", group: "자연"),
        StampKind(id: "rock", title: "바위", symbolName: "mountain.2.fill", group: "자연"),
        StampKind(id: "hill_view", title: "언덕", symbolName: "mountain.2", group: "자연"),
        StampKind(id: "reeds", title: "갈대밭", symbolName: "laurel.leading", group: "자연"),
        StampKind(id: "bamboo", title: "대나무", symbolName: "leaf.arrow.circlepath", group: "자연"),
        StampKind(id: "garden", title: "텃밭", symbolName: "carrot.fill", group: "자연"),
        StampKind(id: "forest", title: "숲길", symbolName: "tree.circle.fill", group: "자연"),
        StampKind(id: "sunset", title: "노을 보이는 곳", symbolName: "sunset.fill", group: "자연"),
        StampKind(id: "sunrise", title: "해 뜨는 곳", symbolName: "sunrise.fill", group: "자연"),
        StampKind(id: "night_sky", title: "별 보이는 곳", symbolName: "moon.stars.fill", group: "자연"),
        StampKind(id: "river", title: "강가", symbolName: "water.waves.slash", group: "자연"),
        StampKind(id: "sea", title: "바다 보임", symbolName: "sailboat.fill", group: "자연"),
        StampKind(id: "snow_spot", title: "눈 쌓이는 곳", symbolName: "snowflake", group: "자연"),
        StampKind(id: "fog_spot", title: "안개 끼는 곳", symbolName: "cloud.fog.fill", group: "자연"),
        StampKind(id: "scent", title: "좋은 냄새", symbolName: "nose.fill", group: "자연"),
        StampKind(id: "cat", title: "길고양이", symbolName: "pawprint.fill", group: "동물"),
        StampKind(id: "dog_bark", title: "개 짖는 집", symbolName: "pawprint", group: "동물"),
        StampKind(id: "dog_park", title: "반려견 놀이터", symbolName: "dog.fill", group: "동물"),
        StampKind(id: "bird", title: "새 많은 곳", symbolName: "bird.fill", group: "동물"),
        StampKind(id: "duck", title: "오리", symbolName: "bird", group: "동물"),
        StampKind(id: "squirrel", title: "다람쥐", symbolName: "hare.fill", group: "동물"),
        StampKind(id: "fish", title: "물고기 보임", symbolName: "fish.fill", group: "동물"),
        StampKind(id: "insect", title: "벌레 많음", symbolName: "ant.fill", group: "동물"),
        StampKind(id: "bee", title: "벌 조심", symbolName: "ladybug.fill", group: "동물"),
        StampKind(id: "cat_food", title: "고양이 밥자리", symbolName: "fork.knife", group: "동물"),
        StampKind(id: "turtle", title: "거북이", symbolName: "tortoise.fill", group: "동물"),
        StampKind(id: "butterfly", title: "나비", symbolName: "sparkles", group: "동물"),
        StampKind(id: "convenience", title: "편의점", symbolName: "bag.fill", group: "가게"),
        StampKind(id: "cafe", title: "카페", symbolName: "cup.and.saucer.fill", group: "가게"),
        StampKind(id: "bakery", title: "빵집", symbolName: "birthday.cake.fill", group: "가게"),
        StampKind(id: "pharmacy", title: "약국", symbolName: "cross.case.fill", group: "가게"),
        StampKind(id: "hospital", title: "병원", symbolName: "cross.fill", group: "가게"),
        StampKind(id: "dentist", title: "치과", symbolName: "mouth.fill", group: "가게"),
        StampKind(id: "salon", title: "미용실", symbolName: "scissors", group: "가게"),
        StampKind(id: "laundry", title: "세탁소", symbolName: "washer.fill", group: "가게"),
        StampKind(id: "stationery", title: "문구점", symbolName: "pencil.and.ruler.fill", group: "가게"),
        StampKind(id: "bookstore", title: "서점", symbolName: "books.vertical.fill", group: "가게"),
        StampKind(id: "florist", title: "꽃집", symbolName: "camera.macro", group: "가게"),
        StampKind(id: "butcher", title: "정육점", symbolName: "fork.knife.circle.fill", group: "가게"),
        StampKind(id: "market", title: "시장", symbolName: "cart.fill", group: "가게"),
        StampKind(id: "supermarket", title: "마트", symbolName: "basket.fill", group: "가게"),
        StampKind(id: "gas_station", title: "주유소", symbolName: "fuelpump.fill", group: "가게"),
        StampKind(id: "bank", title: "은행", symbolName: "banknote.fill", group: "가게"),
        StampKind(id: "post_office", title: "우체국", symbolName: "envelope.fill", group: "가게"),
        StampKind(id: "hardware", title: "철물점", symbolName: "wrench.and.screwdriver.fill", group: "가게"),
        StampKind(id: "phone_shop", title: "휴대폰 가게", symbolName: "iphone", group: "가게"),
        StampKind(id: "clothes", title: "옷가게", symbolName: "tshirt.fill", group: "가게"),
        StampKind(id: "shoes_shop", title: "신발가게", symbolName: "shoe.fill", group: "가게"),
        StampKind(id: "optician", title: "안경점", symbolName: "eyeglasses", group: "가게"),
        StampKind(id: "photo_studio", title: "사진관", symbolName: "camera.fill", group: "가게"),
        StampKind(id: "bike_shop", title: "자전거 가게", symbolName: "bicycle", group: "가게"),
        StampKind(id: "pet_shop", title: "반려동물 가게", symbolName: "pawprint.circle.fill", group: "가게"),
        StampKind(id: "toy_shop", title: "장난감 가게", symbolName: "teddybear.fill", group: "가게"),
        StampKind(id: "furniture", title: "가구점", symbolName: "sofa.fill", group: "가게"),
        StampKind(id: "repair", title: "수선집", symbolName: "hammer.fill", group: "가게"),
        StampKind(id: "printing", title: "인쇄소", symbolName: "printer.fill", group: "가게"),
        StampKind(id: "liquor", title: "주류점", symbolName: "wineglass.fill", group: "가게"),
        StampKind(id: "restaurant", title: "식당", symbolName: "fork.knife", group: "먹을 곳"),
        StampKind(id: "snack_bar", title: "분식집", symbolName: "takeoutbag.and.cup.and.straw.fill", group: "먹을 곳"),
        StampKind(id: "noodles", title: "국수집", symbolName: "frying.pan.fill", group: "먹을 곳"),
        StampKind(id: "chicken", title: "치킨집", symbolName: "oven.fill", group: "먹을 곳"),
        StampKind(id: "pizza", title: "피자", symbolName: "triangle.fill", group: "먹을 곳"),
        StampKind(id: "burger", title: "햄버거", symbolName: "circle.hexagongrid.fill", group: "먹을 곳"),
        StampKind(id: "sushi", title: "일식", symbolName: "fish", group: "먹을 곳"),
        StampKind(id: "chinese", title: "중식", symbolName: "takeoutbag.and.cup.and.straw", group: "먹을 곳"),
        StampKind(id: "bbq", title: "고깃집", symbolName: "flame", group: "먹을 곳"),
        StampKind(id: "stew", title: "찌개집", symbolName: "cup.and.saucer", group: "먹을 곳"),
        StampKind(id: "street_food", title: "길거리 음식", symbolName: "cart", group: "먹을 곳"),
        StampKind(id: "ice_cream", title: "아이스크림", symbolName: "snowflake.circle.fill", group: "먹을 곳"),
        StampKind(id: "dessert", title: "디저트", symbolName: "birthday.cake", group: "먹을 곳"),
        StampKind(id: "tea", title: "찻집", symbolName: "mug.fill", group: "먹을 곳"),
        StampKind(id: "juice", title: "주스", symbolName: "waterbottle.fill", group: "먹을 곳"),
        StampKind(id: "bar", title: "술집", symbolName: "wineglass", group: "먹을 곳"),
        StampKind(id: "beer", title: "맥줏집", symbolName: "mug", group: "먹을 곳"),
        StampKind(id: "brunch", title: "브런치", symbolName: "sun.horizon.fill", group: "먹을 곳"),
        StampKind(id: "vegetarian", title: "채식", symbolName: "leaf.circle", group: "먹을 곳"),
        StampKind(id: "late_night", title: "늦게까지 하는 곳", symbolName: "moon.fill", group: "먹을 곳"),
        StampKind(id: "cheap_eats", title: "싸고 맛있는 곳", symbolName: "wonsign.circle.fill", group: "먹을 곳"),
        StampKind(id: "takeout", title: "포장 되는 곳", symbolName: "bag", group: "먹을 곳"),
        StampKind(id: "subway", title: "지하철역", symbolName: "tram.fill", group: "시설"),
        StampKind(id: "bus_stop", title: "버스정류장", symbolName: "bus.fill", group: "시설"),
        StampKind(id: "taxi", title: "택시 잡는 곳", symbolName: "car.fill", group: "시설"),
        StampKind(id: "parking", title: "주차장", symbolName: "parkingsign", group: "시설"),
        StampKind(id: "bike_rack", title: "자전거 거치대", symbolName: "bicycle.circle.fill", group: "시설"),
        StampKind(id: "bike_share", title: "공공자전거", symbolName: "bicycle.circle", group: "시설"),
        StampKind(id: "ev_charger", title: "전기차 충전", symbolName: "bolt.car.fill", group: "시설"),
        StampKind(id: "parcel_locker", title: "무인택배함", symbolName: "shippingbox.fill", group: "시설"),
        StampKind(id: "atm", title: "현금인출기", symbolName: "creditcard.fill", group: "시설"),
        StampKind(id: "public_phone", title: "공중전화", symbolName: "phone.fill", group: "시설"),
        StampKind(id: "hydrant", title: "소화전", symbolName: "flame.circle.fill", group: "시설"),
        StampKind(id: "police_box", title: "방범초소", symbolName: "shield.fill", group: "시설"),
        StampKind(id: "library", title: "도서관", symbolName: "building.columns.fill", group: "시설"),
        StampKind(id: "community_center", title: "주민센터", symbolName: "building.2.fill", group: "시설"),
        StampKind(id: "school", title: "학교", symbolName: "graduationcap.fill", group: "시설"),
        StampKind(id: "kindergarten", title: "유치원", symbolName: "figure.and.child.holdinghands", group: "시설"),
        StampKind(id: "park", title: "공원", symbolName: "tree.circle", group: "시설"),
        StampKind(id: "playground", title: "놀이터", symbolName: "figure.play", group: "시설"),
        StampKind(id: "church", title: "교회", symbolName: "building.columns", group: "시설"),
        StampKind(id: "temple", title: "절", symbolName: "house.and.flag.fill", group: "시설"),
        StampKind(id: "museum", title: "박물관", symbolName: "building.columns.circle.fill", group: "시설"),
        StampKind(id: "theater", title: "극장", symbolName: "theatermasks.fill", group: "시설"),
        StampKind(id: "recycling", title: "재활용", symbolName: "arrow.3.trianglepath", group: "시설"),
        StampKind(id: "trash", title: "쓰레기통", symbolName: "trash.fill", group: "시설"),
        StampKind(id: "clothing_bin", title: "의류수거함", symbolName: "tshirt", group: "시설"),
        StampKind(id: "elevator", title: "엘리베이터", symbolName: "arrow.up.arrow.down.square.fill", group: "시설"),
        StampKind(id: "escalator", title: "에스컬레이터", symbolName: "arrow.up.right.square.fill", group: "시설"),
        StampKind(id: "info_board", title: "안내판", symbolName: "info.circle.fill", group: "시설"),
        StampKind(id: "clock_tower", title: "시계", symbolName: "clock.fill", group: "시설"),
        StampKind(id: "cctv", title: "CCTV", symbolName: "video.fill", group: "시설"),
        StampKind(id: "gym_outdoor", title: "운동기구", symbolName: "dumbbell.fill", group: "운동·놀이"),
        StampKind(id: "basketball", title: "농구장", symbolName: "basketball.fill", group: "운동·놀이"),
        StampKind(id: "soccer", title: "축구장", symbolName: "soccerball", group: "운동·놀이"),
        StampKind(id: "tennis", title: "테니스장", symbolName: "tennis.racket", group: "운동·놀이"),
        StampKind(id: "badminton", title: "배드민턴장", symbolName: "figure.badminton", group: "운동·놀이"),
        StampKind(id: "swimming", title: "수영장", symbolName: "figure.pool.swim", group: "운동·놀이"),
        StampKind(id: "gym", title: "체육관", symbolName: "figure.strengthtraining.traditional", group: "운동·놀이"),
        StampKind(id: "track", title: "달리기 트랙", symbolName: "figure.run", group: "운동·놀이"),
        StampKind(id: "bike_path", title: "자전거길", symbolName: "bicycle", group: "운동·놀이"),
        StampKind(id: "yoga", title: "요가·스트레칭 자리", symbolName: "figure.yoga", group: "운동·놀이"),
        StampKind(id: "climbing", title: "오를 곳", symbolName: "figure.climbing", group: "운동·놀이"),
        StampKind(id: "skate", title: "스케이트장", symbolName: "figure.skating", group: "운동·놀이"),
        StampKind(id: "baseball", title: "야구장", symbolName: "baseball.fill", group: "운동·놀이"),
        StampKind(id: "volleyball", title: "배구장", symbolName: "volleyball.fill", group: "운동·놀이"),
        StampKind(id: "pingpong", title: "탁구대", symbolName: "figure.table.tennis", group: "운동·놀이"),
        StampKind(id: "golf", title: "골프연습장", symbolName: "figure.golf", group: "운동·놀이"),
        StampKind(id: "dark", title: "밤에 어두움", symbolName: "moon.zzz.fill", group: "조심"),
        StampKind(id: "slippery", title: "미끄러움", symbolName: "drop.degreesign.fill", group: "조심"),
        StampKind(id: "many_cars", title: "차 많음", symbolName: "car.2.fill", group: "조심"),
        StampKind(id: "many_bikes", title: "자전거·킥보드 많음", symbolName: "scooter", group: "조심"),
        StampKind(id: "construction", title: "공사 중", symbolName: "cone.fill", group: "조심"),
        StampKind(id: "steep_stairs", title: "계단 가파름", symbolName: "figure.stairs", group: "조심"),
        StampKind(id: "puddle", title: "물 고임", symbolName: "drop.triangle", group: "조심"),
        StampKind(id: "ice", title: "빙판", symbolName: "snowflake.circle", group: "조심"),
        StampKind(id: "falling", title: "낙석·낙하물", symbolName: "exclamationmark.triangle.fill", group: "조심"),
        StampKind(id: "bugs", title: "벌레 많음", symbolName: "ant", group: "조심"),
        StampKind(id: "smell", title: "냄새 남", symbolName: "nose", group: "조심"),
        StampKind(id: "noisy", title: "시끄러움", symbolName: "speaker.wave.3.fill", group: "조심"),
        StampKind(id: "crowded", title: "사람 많음", symbolName: "person.3.fill", group: "조심"),
        StampKind(id: "no_light", title: "가로등 없음", symbolName: "lightbulb.slash.fill", group: "조심"),
        StampKind(id: "blind_corner", title: "시야 막힘", symbolName: "eye.slash.fill", group: "조심"),
        StampKind(id: "dog_off_leash", title: "목줄 안 한 개", symbolName: "pawprint.circle", group: "조심"),
        StampKind(id: "uneven", title: "바닥 울퉁불퉁", symbolName: "waveform.path", group: "조심"),
        StampKind(id: "flood", title: "비 오면 잠김", symbolName: "cloud.heavyrain.fill", group: "조심"),
        StampKind(id: "favorite", title: "가장 좋아하는 자리", symbolName: "heart.fill", group: "기억"),
        StampKind(id: "photo_spot", title: "사진 찍은 곳", symbolName: "camera.viewfinder", group: "기억"),
        StampKind(id: "first_time", title: "처음 와 본 곳", symbolName: "star.fill", group: "기억"),
        StampKind(id: "met_here", title: "여기서 만났다", symbolName: "person.2.fill", group: "기억"),
        StampKind(id: "good_view", title: "내다보이는 곳", symbolName: "binoculars.fill", group: "기억"),
        StampKind(id: "secret", title: "나만 아는 곳", symbolName: "key.fill", group: "기억"),
        StampKind(id: "changed", title: "달라진 곳", symbolName: "arrow.triangle.2.circlepath", group: "기억"),
        StampKind(id: "gone", title: "없어질 곳", symbolName: "hourglass", group: "기억"),
        StampKind(id: "come_back", title: "다시 오고 싶다", symbolName: "arrow.uturn.left.circle.fill", group: "기억"),
        StampKind(id: "with_dog", title: "개와 함께 온 곳", symbolName: "pawprint.circle.fill", group: "기억"),
        StampKind(id: "with_family", title: "같이 온 곳", symbolName: "figure.2.and.child.holdinghands", group: "기억"),
        StampKind(id: "rested", title: "오래 머문 곳", symbolName: "zzz", group: "기억"),
        StampKind(id: "bookmark", title: "표시해 둘 곳", symbolName: "bookmark.fill", group: "기억"),
        StampKind(id: "note", title: "적어 둘 것", symbolName: "note.text", group: "기억"),
        StampKind(id: "other", title: "그 밖", symbolName: "seal.fill", group: "기억"),
    ]

    /// id로 빠르게 찾기 위한 표
    private static let byID: [String: StampKind] = Dictionary(
        all.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    static let fallback = StampKind(id: "other", title: "그 밖", symbolName: "seal.fill", group: "기억")

    /// 저장된 id가 목록에 없으면 '그 밖'으로 떨어뜨린다 (앱이 깨지지 않게)
    static func kind(id: String) -> StampKind {
        byID[id] ?? fallback
    }

    static func kinds(in group: String) -> [StampKind] {
        all.filter { $0.group == group }
    }

    /// 이름으로 찾기. 200가지가 넘어 훑어보기만으로는 못 찾는다.
    static func search(_ text: String) -> [StampKind] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}
