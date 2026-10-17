#!/usr/bin/env python3
"""그림지도 스프라이트를 SVG로 그려 에셋 카탈로그(밝은/어두운 두 벌)에 넣는다.

사용: python3 scripts/make_terrain_art.py FootprintDiary/Assets.xcassets [<미리보기 폴더>]
모든 그림은 viewBox를 pt 크기의 10배로 잡는다. 아래 가운데가 발 딛는 자리다.
"""
import json
import os
import sys

LIGHT = dict(
    line="#3F663D", shadow="#40591F", shadowA=0.20, hi="#FFFFFF", hiA=0.70,
    peak="#8BC873", peakTop="#A9DB8A", peakShade="#69A85F", peakBack="#B9DF95", peakBackShade="#9CCB7F",
    snow="#FFFFFF", snowShade="#DCEAF2", blush="#FF8C99", blushA=0.75, eye="#2F4A2E",
    leaf="#74BD5F", leafTop="#A6DD7F", leafShade="#58A04C", pine="#459469", pineTop="#68B585", pineShade="#357A55",
    blossom="#FDB6CB", blossomTop="#FFD9E4", blossomShade="#EE93AE", bloom="#FFFFFF",
    autumn="#FCAF55", autumnTop="#FFD28A", autumnShade="#E58B3A",
    trunk="#9A6D4C", trunkShade="#7C5539", berry="#E2586A",
    wave="#FFFFFF", waveShade="#6FAED0", waveShadeA=0.55,
    hull="#DB614D", hullShade="#B54A3A", sail="#FFFFFF", sailShade="#E4EEF2", flag="#F6C344", mast="#7C5539",
    duck="#FFDB59", duckShade="#F0BE3A", beak="#FF8C40",
    grass="#8CB86B", grassDark="#6E9E52", petal="#FFCCD6", petalAlt="#FFFFFF", center="#FFD24D",
)
DARK = dict(
    line="#9EBD94", shadow="#000000", shadowA=0.35, hi="#FFFFFF", hiA=0.22,
    peak="#4D704C", peakTop="#5E8459", peakShade="#3B5A3D", peakBack="#3E5745", peakBackShade="#33493A",
    snow="#CDD6DB", snowShade="#A9B6BE", blush="#CC737F", blushA=0.65, eye="#1C2A1C",
    leaf="#527A4A", leafTop="#6B925C", leafShade="#41643C", pine="#386650", pineTop="#4B7D63", pineShade="#2C5341",
    blossom="#B27589", blossomTop="#C690A2", blossomShade="#965F72", bloom="#E4D8DC",
    autumn="#B87A3D", autumnTop="#CC9455", autumnShade="#9A6230",
    trunk="#6B523D", trunkShade="#55402F", berry="#B4525E",
    wave="#8FB6CF", waveShade="#000000", waveShadeA=0.30,
    hull="#9E5243", hullShade="#7F4136", sail="#D9DCD8", sailShade="#B9C0BE", flag="#C9A240", mast="#55402F",
    duck="#D9BD5C", duckShade="#BA9E45", beak="#DB8542",
    grass="#5C7A51", grassDark="#4A6542", petal="#C79EAA", petalAlt="#D6D0CC", center="#C9A54A",
)

LINE_W = 11  # 1.1pt


def svg(w, h, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w * 10} {h * 10}">\n{body}\n</svg>\n')


def shadow(p, cx, cy, rx, ry):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{p["shadow"]}" fill-opacity="{p["shadowA"]}"/>'


def stroke_path(d, color, width, opacity=1.0):
    return (f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" stroke-opacity="{opacity}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')


def filled(d, fill, line=None, width=LINE_W, opacity=1.0):
    s = f' stroke="{line}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"' if line else ''
    o = f' fill-opacity="{opacity}"' if opacity < 1 else ''
    return f'<path d="{d}" fill="{fill}"{o}{s}/>'


def blob(circles, fill, line, width=LINE_W * 2):
    """겹친 동그라미를 하나의 덩어리로 — 테두리를 먼저 굵게 칠하고 그 위에 속을 덮는다."""
    under = ''.join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{line}" stroke="{line}" stroke-width="{width}"/>'
                    for x, y, r in circles)
    over = ''.join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}"/>' for x, y, r in circles)
    return under + over


# MARK: 봉우리 (64 x 50 pt)

def bell(cx, top, left, right, base):
    """꼭대기가 둥근 종 모양 봉우리"""
    hw_l, hw_r = cx - left, right - cx
    h = base - top
    return (f'M{left},{base} '
            f'C{left + hw_l * 0.25},{base - h * 0.12} {cx - hw_l * 0.55},{top + h * 0.55} {cx - hw_l * 0.33},{top + h * 0.25} '
            f'C{cx - hw_l * 0.20},{top + h * 0.06} {cx - hw_l * 0.10},{top} {cx},{top} '
            f'C{cx + hw_r * 0.10},{top} {cx + hw_r * 0.20},{top + h * 0.06} {cx + hw_r * 0.33},{top + h * 0.25} '
            f'C{cx + hw_r * 0.55},{top + h * 0.55} {right - hw_r * 0.25},{base - h * 0.12} {right},{base} Z')


def bell_shade(cx, top, left, right, base):
    """오른쪽 그늘 — 꼭대기에서 비스듬히 내려와 오른쪽 자락을 덮는다"""
    hw_r = right - cx
    h = base - top
    return (f'M{cx + hw_r * 0.05},{top + 2} '
            f'C{cx + hw_r * 0.20},{top + h * 0.06} {cx + hw_r * 0.25},{top + h * 0.15} {cx + hw_r * 0.33},{top + h * 0.25} '
            f'C{cx + hw_r * 0.55},{top + h * 0.55} {right - hw_r * 0.25},{base - h * 0.12} {right},{base} '
            f'L{cx + hw_r * 0.12},{base} '
            f'C{cx + hw_r * 0.30},{top + h * 0.6} {cx + hw_r * 0.18},{top + h * 0.25} {cx + hw_r * 0.05},{top + 2} Z')


def peak(p, cx, top, left, right, base, back=False, ticks=True):
    fill, shade = (p['peakBack'], p['peakBackShade']) if back else (p['peak'], p['peakShade'])
    h = base - top
    hw = cx - left
    out = filled(bell(cx, top, left, right, base), fill)
    out += filled(bell_shade(cx, top, left, right, base), shade)
    if not back:
        # 꼭대기 쪽이 조금 밝은 물감 번짐
        out += (f'<ellipse cx="{cx - hw * 0.10}" cy="{top + h * 0.36}" rx="{hw * 0.13}" ry="{h * 0.17}" '
                f'fill="{p["peakTop"]}" fill-opacity="0.6"/>')
    out += filled(bell(cx, top, left, right, base), 'none', p['line'])
    # 왼쪽 비탈의 빛줄기
    out += stroke_path(f'M{cx - hw * 0.42},{top + h * 0.40} Q{cx - hw * 0.30},{top + h * 0.18} {cx - hw * 0.12},{top + h * 0.07}',
                       p['hi'], 13, p['hiA'])
    if ticks:
        # 풀결 — 작은 V자
        for fx, fy in ((-0.55, 0.78), (-0.15, 0.62), (0.35, 0.72), (0.62, 0.86), (-0.30, 0.90)):
            x, y = cx + hw * fx, top + h * fy
            out += stroke_path(f'M{x - 12},{y - 9} L{x},{y + 4} L{x + 12},{y - 9}', p['line'], 7, 0.45)
    return out


def snowcap(p, cx, top, left, right, base):
    hw_l, hw_r = cx - left, right - cx
    h = base - top
    y = top + h * 0.30
    xl, xr = cx - hw_l * 0.36, cx + hw_r * 0.36
    d = (f'M{xl},{y} '
         f'C{cx - hw_l * 0.24},{top + h * 0.09} {cx - hw_l * 0.10},{top} {cx},{top} '
         f'C{cx + hw_r * 0.10},{top} {cx + hw_r * 0.24},{top + h * 0.09} {xr},{y} ')
    # 아래 가장자리는 녹아내린 듯 물결 모양
    steps = 5
    for i in range(steps):
        x0 = xr - (xr - xl) * i / steps
        x1 = xr - (xr - xl) * (i + 1) / steps
        dip = 26 if i % 2 == 0 else 14
        d += f'Q{(x0 + x1) / 2},{y + dip} {x1},{y} '
    d += 'Z'
    shade_d = (f'M{cx + 4},{top + 3} C{cx + hw_r * 0.12},{top + 2} {cx + hw_r * 0.24},{top + h * 0.09} {xr},{y} '
               f'Q{xr - 20},{y + 22} {cx + hw_r * 0.12},{y + 4} C{cx + hw_r * 0.14},{top + h * 0.15} {cx + 8},{top + h * 0.05} {cx + 4},{top + 3} Z')
    return filled(d, p['snow'], p['line'], 9) + filled(shade_d, p['snowShade'])


def mountains(p):
    W, H = 64, 50
    base = 470
    out = {}
    out['TerrainMountain1'] = svg(W, H, shadow(p, 320, 478, 270, 20) + peak(p, 320, 70, 50, 590, base))
    out['TerrainMountain2'] = svg(W, H, shadow(p, 330, 478, 290, 20)
                                  + peak(p, 220, 150, 20, 430, base, back=True, ticks=False)
                                  + peak(p, 390, 75, 150, 625, base))
    out['TerrainMountain3'] = svg(W, H, shadow(p, 320, 478, 300, 20)
                                  + peak(p, 160, 175, 10, 330, base, back=True, ticks=False)
                                  + peak(p, 485, 160, 300, 630, base, back=True, ticks=False)
                                  + peak(p, 320, 65, 110, 530, base))
    out['TerrainMountain4'] = svg(W, H, shadow(p, 320, 478, 290, 20)
                                  + peak(p, 320, 35, 30, 610, base) + snowcap(p, 320, 35, 30, 610, base))
    face = (f'<circle cx="282" cy="300" r="13" fill="{p["eye"]}"/><circle cx="358" cy="300" r="13" fill="{p["eye"]}"/>'
            f'<circle cx="286" cy="295" r="4.5" fill="#FFFFFF"/><circle cx="362" cy="295" r="4.5" fill="#FFFFFF"/>'
            + stroke_path('M300,332 Q320,352 340,332', p['eye'], 9)
            + f'<ellipse cx="248" cy="335" rx="24" ry="13" fill="{p["blush"]}" fill-opacity="{p["blushA"]}"/>'
            + f'<ellipse cx="392" cy="335" rx="24" ry="13" fill="{p["blush"]}" fill-opacity="{p["blushA"]}"/>')
    out['TerrainMountain5'] = svg(W, H, shadow(p, 320, 478, 270, 20) + peak(p, 320, 70, 50, 590, base, ticks=False) + face)
    return out


# MARK: 나무 (24 x 30 pt)

def trunk(p, x=120, top=185, bottom=282, w=26):
    return (f'<rect x="{x - w / 2}" y="{top}" width="{w}" height="{bottom - top}" rx="{w / 2}" fill="{p["trunk"]}" '
            f'stroke="{p["line"]}" stroke-width="{LINE_W}"/>'
            f'<rect x="{x + 1}" y="{top + 8}" width="{w / 2 - 6}" height="{bottom - top - 16}" rx="5" fill="{p["trunkShade"]}"/>')


def crown(p, circles, fill, top_fill, shade_fill, dots=None):
    out = blob(circles, fill, p['line'])
    # 오른쪽 아래 그늘, 왼쪽 위 밝은 번짐
    xs = [c[0] for c in circles]
    ys = [c[1] for c in circles]
    cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
    for x, y, r in circles:
        if x >= cx - 5 and y >= cy - 10:
            out += f'<circle cx="{x + r * 0.18}" cy="{y + r * 0.20}" r="{r * 0.72}" fill="{shade_fill}" fill-opacity="0.75"/>'
    top = min(circles, key=lambda c: c[1] - c[2])
    out += f'<circle cx="{top[0] - top[2] * 0.25}" cy="{top[1] - top[2] * 0.22}" r="{top[2] * 0.55}" fill="{top_fill}" fill-opacity="0.9"/>'
    out += f'<circle cx="{top[0] - top[2] * 0.38}" cy="{top[1] - top[2] * 0.38}" r="{top[2] * 0.16}" fill="{p["hi"]}" fill-opacity="{p["hiA"]}"/>'
    for x, y, r, c in dots or []:
        out += f'<circle cx="{x}" cy="{y}" r="{r}" fill="{c}"/>'
    return out


def trees(p):
    W, H = 24, 30
    out = {}
    ground = lambda rx=78: shadow(p, 120, 286, rx, 11)
    round_crown = [(78, 150, 50), (162, 150, 50), (120, 92, 62), (120, 160, 52)]
    out['TerrainTree1'] = svg(W, H, ground() + trunk(p) + crown(p, round_crown, p['leaf'], p['leafTop'], p['leafShade']))

    # 침엽수 — 세 층의 둥근 세모
    tiers = [(205, 85, 238), (145, 70, 180), (90, 52, 122)]
    pine = ''
    under = ''
    for apex, half, base in tiers:
        d = f'M120,{apex - 60} Q{120 - half * 0.3},{apex} {120 - half},{base} Q120,{base + 18} {120 + half},{base} Q{120 + half * 0.3},{apex} 120,{apex - 60} Z'
        under += filled(d, p['line'], p['line'], LINE_W * 2)
        pine += filled(d, p['pine'])
        shade = f'M122,{apex - 50} Q{120 + half * 0.3},{apex} {120 + half},{base} Q{120 + half * 0.5},{base + 12} {126},{base + 8} Q{132},{apex} 122,{apex - 50} Z'
        pine += filled(shade, p['pineShade'])
        pine += stroke_path(f'M{112},{apex - 40} Q{120 - half * 0.45},{apex + 5} {120 - half * 0.7},{base - 10}', p['pineTop'], 12, 0.9)
    out['TerrainTree2'] = svg(W, H, ground(70) + trunk(p, top=225, w=24) + under + pine)

    bloom_dots = [(88, 130, 9, p['bloom']), (150, 110, 8, p['bloom']), (130, 170, 9, p['bloom']), (100, 80, 7, p['bloom']),
                  (170, 160, 7, p['blossomShade']), (75, 170, 7, p['blossomShade']), (140, 70, 6, p['blossomShade'])]
    out['TerrainTree3'] = svg(W, H, ground() + trunk(p) + crown(p, round_crown, p['blossom'], p['blossomTop'], p['blossomShade'], bloom_dots))

    tall = [(120, 75, 52), (95, 135, 52), (145, 135, 52), (120, 170, 48)]
    leaf_dots = [(98, 112, 7, p['autumnShade']), (150, 150, 7, p['autumnShade']), (120, 190, 6, p['autumnShade'])]
    out['TerrainTree4'] = svg(W, H, ground(70) + trunk(p, top=200) + crown(p, tall, p['autumn'], p['autumnTop'], p['autumnShade'], leaf_dots))

    bush = [(70, 238, 42), (170, 238, 42), (120, 215, 55), (120, 248, 40)]
    berries = [(85, 225, 8, p['berry']), (150, 210, 8, p['berry']), (170, 245, 7, p['berry']), (110, 250, 7, p['berry'])]
    out['TerrainTree5'] = svg(W, H, ground(95) + crown(p, bush, p['leaf'], p['leafTop'], p['leafShade'], berries))
    return out


# MARK: 물 위의 것들

def water_things(p):
    out = {}
    # 물결 28 x 12 — 첫 마루 끝이 말려 있다
    wave = 'M25,88 Q72,24 128,80 Q172,40 210,72 Q232,58 255,84'
    out['TerrainWave'] = svg(28, 12, f'<g transform="translate(0,10)">{stroke_path(wave, p["waveShade"], 16, p["waveShadeA"])}</g>'
                             + stroke_path(wave, p['wave'], 15))

    # 돛단배 26 x 28
    hull = 'M22,190 L238,190 Q222,250 182,258 L78,258 Q38,250 22,190 Z'
    boat = (shadow(p, 130, 266, 105, 10)
            + filled('M138,48 L138,180 L232,180 Q205,105 138,48 Z', p['sail'], p['line'])
            + filled('M150,92 L150,174 L224,174 Q210,130 150,92 Z', p['sailShade'])
            + filled('M122,78 L122,180 L50,180 Q72,120 122,78 Z', p['sail'], p['line'])
            + stroke_path('M130,30 L130,190', p['mast'], 12)
            + filled('M132,24 L178,38 L132,52 Z', p['flag'], p['line'], 8)
            + filled(hull, p['hull'], p['line'])
            + filled('M140,190 L238,190 Q222,250 182,258 L140,258 Z', p['hullShade'], opacity=0.8)
            + filled(hull, 'none', p['line'])
            + stroke_path('M40,214 L220,214', p['sail'], 10, 0.9)
            + stroke_path('M10,272 Q40,258 70,272 M190,272 Q220,258 250,272', p['wave'], 10))
    out['TerrainBoat'] = svg(26, 28, boat)

    # 오리 24 x 20
    body = 'M28,128 Q22,92 52,98 Q90,108 120,112 Q178,110 205,128 Q215,170 160,180 L80,180 Q30,176 28,128 Z'
    duck = (shadow(p, 120, 186, 95, 9)
            + filled(body, p['duck'], p['line'])
            + filled('M120,175 Q170,176 198,140 Q212,165 160,180 L110,180 Z', p['duckShade'])
            + filled(body, 'none', p['line'])
            + stroke_path('M78,132 Q108,158 140,132', p['line'], 9, 0.7)
            + f'<circle cx="160" cy="70" r="40" fill="{p["duck"]}" stroke="{p["line"]}" stroke-width="{LINE_W}"/>'
            + filled('M194,70 Q228,66 232,82 Q226,96 194,90 Z', p['beak'], p['line'], 9)
            + f'<circle cx="168" cy="62" r="7" fill="{p["eye"]}"/><circle cx="170" cy="59" r="2.5" fill="#FFFFFF"/>'
            + f'<ellipse cx="150" cy="84" rx="12" ry="7" fill="{p["blush"]}" fill-opacity="{p["blushA"]}"/>'
            + stroke_path('M20,192 Q50,180 80,192 M160,192 Q190,180 220,192', p['wave'], 9))
    out['TerrainDuck'] = svg(24, 20, duck)
    return out


# MARK: 빈 뭍의 풀포기·들꽃

def ground_things(p):
    out = {}
    blades = ''
    for x, top, lean, c in ((30, 32, -14, p['grassDark']), (52, 8, -4, p['grass']), (70, 22, 10, p['grassDark']),
                            (90, 40, 18, p['grass'])):
        blades += filled(f'M{x - 9},88 Q{x - 4 + lean * 0.3},{(88 + top) / 2} {x + lean},{top} Q{x + 6 + lean * 0.3},{(88 + top) / 2} {x + 9},88 Z', c)
    out['TerrainTuft'] = svg(12, 9, blades)

    import math
    petals = ''
    for i in range(5):
        a = -math.pi / 2 + i * 2 * math.pi / 5
        petals += f'<circle cx="{50 + 17 * math.cos(a):.1f}" cy="{42 + 17 * math.sin(a):.1f}" r="13" fill="{p["petal"]}"/>'
    flower = (stroke_path('M50,52 Q46,75 50,96', p['grassDark'], 7)
              + filled('M50,82 Q30,70 26,80 Q36,90 50,86 Z', p['grass'])
              + petals
              + f'<circle cx="50" cy="42" r="10" fill="{p["center"]}"/>')
    out['TerrainFlower'] = svg(10, 10, flower)
    return out


def all_art(p):
    art = {}
    for part in (mountains, trees, water_things, ground_things):
        art.update(part(p))
    return art


def main():
    catalog = sys.argv[1]
    preview = sys.argv[2] if len(sys.argv) > 2 else None
    folder = os.path.join(catalog, 'Terrain')
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, 'Contents.json'), 'w') as f:
        json.dump({'info': {'author': 'xcode', 'version': 1}}, f, indent=2)
    light, dark = all_art(LIGHT), all_art(DARK)
    for name in light:
        imageset = os.path.join(folder, f'{name}.imageset')
        os.makedirs(imageset, exist_ok=True)
        for suffix, art in (('', light), ('-dark', dark)):
            with open(os.path.join(imageset, f'{name}{suffix}.svg'), 'w') as f:
                f.write(art[name])
        contents = {
            'images': [
                {'filename': f'{name}.svg', 'idiom': 'universal'},
                {'appearances': [{'appearance': 'luminosity', 'value': 'dark'}],
                 'filename': f'{name}-dark.svg', 'idiom': 'universal'},
            ],
            'info': {'author': 'xcode', 'version': 1},
            'properties': {'preserves-vector-representation': True},
        }
        with open(os.path.join(imageset, 'Contents.json'), 'w') as f:
            json.dump(contents, f, indent=2)
    if preview:
        # 한 장에 모아 보기
        os.makedirs(preview, exist_ok=True)
        for tag, art, bg in (('light', light, '#FAF5E3'), ('dark', dark, '#1A1A1F')):
            cells = ''
            x, row = 20, 0
            for i, (name, s) in enumerate(art.items()):
                if i in (5, 10):
                    x, row = 20, row + 1
                inner = s.split('\n', 1)[1].rsplit('</svg>', 1)[0]
                w = float(s.split('width="')[1].split('"')[0])
                h = float(s.split('height="')[1].split('"')[0])
                scale = 4 if name.startswith("TerrainMountain") else 6
                cells += (f'<g transform="translate({x},{240 * row + 220 - h * scale}) scale({scale / 10})">{inner}</g>')
                x += w * scale + 20
            board = (f'<svg xmlns="http://www.w3.org/2000/svg" width="1500" height="740">'
                     f'<rect width="100%" height="100%" fill="{bg}"/>{cells}</svg>')
            with open(os.path.join(preview, f'board-{tag}.svg'), 'w') as f:
                f.write(board)


if __name__ == '__main__':
    main()
