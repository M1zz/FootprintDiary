#!/bin/sh
# 배포 전 게이트 — 여기서 실패하면 DeployBar 가 아카이브를 만들지 않는다.
#
# 사용법:
#   sh scripts/predeploy.sh
#
# 다국어(.xcstrings) 검사는 DeployBar 에 내장돼 있으므로 여기서 다시 하지 않는다.
# 이 스크립트는 "이 앱만의" 검사를 담는다.
#
# ⚠️ 이 앱에는 테스트 타겟이 없다.
#    그래서 이 게이트는 `xcodebuild test` 가 아니라 Release 빌드가 끝까지 서는지만 본다.
#    "고장 나지 않았다"가 아니라 "컴파일은 된다"까지만 말해 주는 게이트다.
#    나중에 테스트 타겟을 만들면 아래 build 를 test 로 바꾸면 된다.
#
# ⚠️ CODE_SIGNING_ALLOWED=NO 로 빌드를 빠르게 만들지 말 것.
#    entitlements 가 빠지면 CloudKit 등 실제 배포 경로에서만 터지는 문제를 놓친다.
set -e
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

SCHEME="FootprintDiary"
PROJECT_FLAG="-project"
PROJECT="FootprintDiary.xcodeproj"
VERSION_XCCONFIG="Version.xcconfig"

# ── 1. 버전 소스가 한 곳인지 ────────────────────────────────────────────
# 타겟이 둘(앱·위젯)이라 project.pbxproj 에 MARKETING_VERSION 을 다시 적으면 그쪽이
# xcconfig 를 이긴다. 그러면 DeployBar 가 올린 버전이 조용히 무시되고, 앱과 위젯의
# 버전이 어긋난 아카이브가 업로드되고 나서야 드러난다. 여기서 미리 막는다.
echo "🔢 버전 소스 확인"
if [ ! -f "$VERSION_XCCONFIG" ]; then
  echo "❌ $VERSION_XCCONFIG 가 없습니다 — deploy.env 의 VERSION_XCCONFIG 와 어긋납니다"
  exit 1
fi
for KEY in MARKETING_VERSION CURRENT_PROJECT_VERSION; do
  if ! grep -qE "^[[:space:]]*$KEY[[:space:]]*=" "$VERSION_XCCONFIG"; then
    echo "❌ $VERSION_XCCONFIG 에 $KEY 줄이 없습니다"
    exit 1
  fi
  if grep -qE "^[[:space:]]*$KEY[[:space:]]*=" "$PROJECT/project.pbxproj"; then
    echo "❌ project.pbxproj 에 $KEY 가 되살아났습니다 — xcconfig 를 이겨 버립니다"
    echo "   (Xcode 타겟 > General 의 Version·Build 칸을 고치면 이렇게 됩니다)"
    echo "   그 줄을 지우고 $VERSION_XCCONFIG 에서만 고쳐 주세요"
    exit 1
  fi
done
echo "   $VERSION_XCCONFIG · $(grep -E '^[[:space:]]*MARKETING_VERSION' "$VERSION_XCCONFIG" | head -1 | tr -s ' ')"

# ── 2. Release 빌드가 서는지 ────────────────────────────────────────────
# 시뮬레이터는 **가장 최신 iOS 런타임의 iPhone** 으로 고른다.
# `grep iPhone | head -1` 로 고르면 구버전 런타임 기기가 먼저 잡혀
# "Unable to find a destination matching..." (exit 70) 로 죽는다.
DEST_ID="$(xcrun simctl list devices available --json | python3 -c '
import json, re, sys
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        if d.get("isAvailable") and "iPhone" in d.get("name", ""):
            if best is None or version > best[0]:
                best = (version, d["udid"])
print(best[1] if best else "")
')"
if [ -z "$DEST_ID" ]; then
  echo "❌ 사용 가능한 iPhone 시뮬레이터가 없습니다"
  xcrun simctl list devices available | head -30
  exit 1
fi
DEST="platform=iOS Simulator,id=$DEST_ID"

# Release 로 짓는 까닭은 아카이브가 Release 로 지어지기 때문이다. Debug 만 보면
# 최적화가 켜져야 드러나는 것들을 게이트가 통과시켜 버린다.
# 앱 스킴을 지으면 위젯 확장도 딸려 지어진다(타겟 의존성 + 임베드).
echo "🔨 Release 빌드 ($SCHEME · 위젯 확장 포함)"
xcodebuild build \
  "$PROJECT_FLAG" "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "$DEST" \
  -quiet

echo ""
echo "✅ 게이트 통과 — 배포 가능 (테스트 타겟이 없어 빌드까지만 확인했습니다)"
