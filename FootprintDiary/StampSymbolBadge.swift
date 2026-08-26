//
//  StampSymbolBadge.swift
//  FootprintDiary
//
//  한 자리의 심볼을 보여 주는 작은 딱지.
//
//  자리마다 따로 그리지 않고 여기 하나로 둔다. 지도에서 간판 사진으로 보이던 자리가
//  목록에서는 '카페' 그림으로 나오면, 같은 곳인 줄 알아보는 데 한 번 더 생각해야 한다.
//  심볼은 '어느 자리인가'를 한눈에 알아보게 하는 것이라, 나오는 곳마다 같아야 제 몫을 한다.
//
//  지도 쪽(StampSeal)과 그림이 완전히 같지는 않다. 저쪽은 30pt 도장 안에 종이를 깔고
//  얹느라 CoreGraphics로 굽고, 이쪽은 목록과 시트에서 쓰는 스위프트UI 뷰다. 하는 일이
//  같으니 언젠가 하나로 합칠 만하지만, 억지로 합치면 MapKit 쪽이 SwiftUI를 끌고 들어온다.
//

import SwiftUI

struct StampSymbolBadge: View {
    let stamp: MapStamp
    var side: CGFloat = 32
    var corner: CGFloat = 8

    var body: some View {
        if let data = stamp.sticker, let image = UIImage(data: data) {
            // 배경이 지워진 그림이라 그대로 얹는다. 뒤에 색을 깔면 목록에서만
            // 네모가 되어, 지도에서 보던 것과 다른 물건처럼 보인다.
            // 흰 테두리가 흰 바탕에 묻히지 않도록 그림자만 옅게 준다.
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
        } else {
            Image(systemName: stamp.kind.symbolName)
                .font(.system(size: side * 0.47, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .background(RoundedRectangle(cornerRadius: corner).fill(Color(InkStyle.sealRed)))
        }
    }
}
