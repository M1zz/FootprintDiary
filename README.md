# 발자국일기 (FootprintDiary) 👣

장소를 옮길 때마다 자동으로 발자국이 쌓이고, 앱을 열면 "여기는 어디였나요?"라고
물어봐 주는 iOS 위치 일기 앱입니다. 하루의 이동 경로를 지도에 발자국으로 보여주고,
날짜별로 사진과 함께 일기를 쓸 수 있습니다.

## 요구 사항

- Xcode 16 이상
- iOS 17.0 이상 (SwiftUI + SwiftData + MapKit 최신 API 사용)
- 실제 자동 위치 기록 테스트는 실기기 권장 (시뮬레이터에서는 위치 시뮬레이션 사용)

## 실행 방법

1. `FootprintDiary.xcodeproj`를 Xcode에서 엽니다.
2. 프로젝트 설정 → **Signing & Capabilities**에서 본인의 **Team**을 선택합니다.
   (Bundle Identifier `com.leeo.FootprintDiary`는 필요하면 자유롭게 바꾸세요.)
3. 실기기 또는 시뮬레이터를 선택하고 **Run(⌘R)** 합니다.
4. 첫 실행 시 위치 권한을 허용해 주세요.
   - 자동 기록을 위해서는 나중에 뜨는 **"항상 허용"** 승급 요청도 허용하는 것이 좋습니다.

## 주요 기능

- **자동 발자국 기록**: iOS의 방문 감지(CLVisit)와 큰 위치 변화 감지를 사용해
  배터리를 거의 쓰지 않고 장소 이동을 자동으로 기록합니다. 앱이 종료돼 있어도
  시스템이 앱을 깨워서 기록합니다. (별도 백그라운드 모드 불필요)
- **앱 열 때 한꺼번에 묻기**: 앱을 열면 아직 이름이 없는 장소들을 순서대로
  "여기는 어디였나요?"라고 물어봅니다. 최근 사용한 이름을 칩으로 제안하고,
  150m 이내의 같은 장소는 이름을 자동으로 재사용합니다.
- **지도 발자국**: 날짜를 고르면 그날의 이동 경로가 번호 붙은 👣 마커와
  점선 경로로 표시됩니다. 마커/목록을 탭해서 이름을 수정하거나 삭제할 수 있습니다.
- **일기**: 날짜별로 텍스트 일기를 쓰고 사진을 첨부할 수 있습니다.
  그날의 발자국 목록이 일기 위에 요약으로 함께 보입니다.
- **수동 기록**: 지도 화면 오른쪽 위 ➕ 버튼으로 지금 위치를 즉시 발자국으로
  남길 수 있습니다. (시뮬레이터 테스트에도 유용)

## 시뮬레이터에서 테스트하기

시뮬레이터는 실제 이동이 없으므로 다음 방법을 사용하세요.

1. 시뮬레이터 메뉴 **Features → Location → Custom Location…** 으로 좌표를 바꾼 뒤
   앱의 ➕ 버튼으로 발자국을 남깁니다. 좌표를 여러 번 바꾸며 반복하면
   하루 경로가 만들어집니다.
2. **Features → Location → City Bicycle Ride / Freeway Drive**를 켜면
   이동 시뮬레이션도 가능합니다.
3. 앱을 껐다 켜면 "여기는 어디였나요?" 시트가 뜹니다.

## 데이터 저장

모든 데이터(발자국, 일기, 사진)는 SwiftData로 **기기 안에만** 저장되며
외부 서버로 전송되지 않습니다.

## 파일 구성

| 파일 | 역할 |
|---|---|
| `FootprintDiaryApp.swift` | 앱 진입점, SwiftData 컨테이너/위치 매니저 초기화 |
| `Models.swift` | Visit(발자국), DiaryEntry(일기), DiaryPhoto(사진) 모델 |
| `LocationManager.swift` | 방문 감지·큰 위치 변화 감지, 발자국 저장, 역지오코딩 |
| `ContentView.swift` | 탭 구성, 앱 열 때 미확인 장소 묻기 |
| `MapScreen.swift` | 날짜별 지도 발자국 + 경로 + 발자국 수정 |
| `PlaceNamingView.swift` | "여기는 어디였나요?" 장소 이름 묻기 시트 |
| `DiaryScreen.swift` | 날짜별 일기 목록 + 텍스트/사진 일기 편집 |

## 문서 · 링크

- 🏠 [소개 페이지](https://m1zz.github.io/FootprintDiary/)
- 🔒 [개인정보 처리방침](https://m1zz.github.io/FootprintDiary/privacy.html)
- 💬 [지원 / 문의](https://m1zz.github.io/FootprintDiary/support.html)
