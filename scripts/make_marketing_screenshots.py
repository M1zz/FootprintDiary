#!/usr/bin/env python3
"""App Store 마케팅 스크린샷: 시뮬레이터 원본 캡처 + 헤드라인 → HTML → 헤드리스 Chrome.

사용법: python3 scripts/make_marketing_screenshots.py [언어 ...]   (없으면 전부)

  원본  docs/screenshots/raw/<언어>/NN-….png         (iPhone 6.9" 시뮬레이터 캡처 1320x2868, 올라가지 않는다)
  제출  docs/screenshots/marketing/<스토어 로케일>/NN-….png   (1242x2688, DeployBar 가 그대로 올린다)

파일 이름 순서가 스토어에 보이는 순서다. 다음 릴리즈에는 원본만 다시 찍고 이 스크립트를 다시 돌린다.
"""
import subprocess, sys, pathlib, tempfile, time

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "screenshots" / "raw"
OUT = ROOT / "docs" / "screenshots" / "marketing"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 1242, 2688   # 이 계정의 iPhone 제출 규격

# ── 앱마다 고치는 곳 ──────────────────────────────────────────────
# 앱 언어 → App Store 로케일 (스토어 폴더 이름)
STORE = {"ko": "ko", "en": "en-US", "en-GB": "en-GB", "ja": "ja", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant", "es": "es-ES", "de": "de-DE", "fr": "fr-FR", "it": "it", "pt-BR": "pt-BR", "ru": "ru", "th": "th", "vi": "vi", "cs": "cs", "da": "da", "el": "el", "fi": "fi", "id": "id", "nb": "no", "nl": "nl-NL", "pl": "pl", "sv": "sv"}
# 바탕 · 포인트 색 (헤더·검색 결과 그림과 맞춘다)
BG, ACCENT, INK, SUB = "#F3EFE4", "#B8322A", "#1F3358", "#6B6458"
# 언어 → [(원본 파일, 레이아웃, 헤드라인, 서브카피)]
SHOTS = {
    "ko": [
        ("01-map.png",      "hero-bleed",  "두 발로 지난 길만<br>남는 백지도", "차로 지난 길은 그려지지 않아요"),
        ("02-compass.png",  "left-text",   "오늘은<br>어느 쪽으로?", "덜 걸어 본 방향을 나침반이 가리켜요"),
        ("03-stamps.png",   "text-bottom", "가본 곳, 가볼 곳에 도장", "212가지 스탬프로 동네를 기록해요"),
        ("04-calendar.png", "flat-rotate", "날마다<br>걸은 모양 그대로", "달력에 숫자 대신 그날의 길이 남아요"),
        ("05-diary.png",    "dark",        "처음 걷는 길이<br>얼마였는지", "같은 길만 걸으면 지도는 자라지 않아요"),
    ],
    "sv": [
        ("01-map.png",      "hero-bleed",  "En tom karta som bara<br>sparar dina steg", "Vägar med bil ritas inte"),
        ("02-compass.png",  "left-text",   "I dag<br>åt vilket håll?", "Kompassen pekar där du gått minst"),
        ("03-stamps.png",   "text-bottom", "Stämplar för besökta platser och mål", "Logga ditt område med 212 stämplar"),
        ("04-calendar.png", "flat-rotate", "Varje dag<br>som du gick den", "Kalendern sparar dagens väg i stället för en siffra"),
        ("05-diary.png",    "dark",        "Hur mycket var<br>ny väg?", "Går du bara samma vägar växer inte kartan"),
    ],
    "pl": [
        ("01-map.png",      "hero-bleed",  "Pusta mapa, która zachowuje<br>tylko Twoje kroki", "Przejazdy samochodem nie są rysowane"),
        ("02-compass.png",  "left-text",   "Dziś<br>w którą stronę?", "Kompas wskazuje, gdzie chodziłeś najmniej"),
        ("03-stamps.png",   "text-bottom", "Pieczątki dla miejsc odwiedzonych i celów", "Zapisz swoją okolicę 212 pieczątkami"),
        ("04-calendar.png", "flat-rotate", "Każdy dzień<br>tak, jak go przeszedłeś", "Kalendarz zachowuje drogę dnia zamiast liczby"),
        ("05-diary.png",    "dark",        "Ile z tego było<br>nową drogą?", "Chodząc tylko tymi samymi drogami, nie powiększysz mapy"),
    ],
    "nl": [
        ("01-map.png",      "hero-bleed",  "Een lege kaart die alleen<br>je stappen bewaart", "Wegen met de auto worden niet getekend"),
        ("02-compass.png",  "left-text",   "Welke kant<br>op vandaag?", "Het kompas wijst waar je het minst bent geweest"),
        ("03-stamps.png",   "text-bottom", "Stempels voor bezochte plekken en doelen", "Leg je buurt vast met 212 stempels"),
        ("04-calendar.png", "flat-rotate", "Elke dag<br>zoals je hem liep", "De kalender bewaart de weg van de dag in plaats van een getal"),
        ("05-diary.png",    "dark",        "Hoeveel was er<br>een nieuwe weg?", "Wie alleen dezelfde wegen loopt, laat de kaart niet groeien"),
    ],
    "nb": [
        ("01-map.png",      "hero-bleed",  "Et tomt kart som bare<br>tar vare på skrittene dine", "Bilveier tegnes ikke"),
        ("02-compass.png",  "left-text",   "I dag<br>hvilken vei?", "Kompasset peker mot der du har gått minst"),
        ("03-stamps.png",   "text-bottom", "Stempler for besøkte steder og mål", "Registrer nabolaget ditt med 212 stempler"),
        ("04-calendar.png", "flat-rotate", "Hver dag<br>slik du gikk den", "Kalenderen tar vare på dagens vei i stedet for et tall"),
        ("05-diary.png",    "dark",        "Hvor mye var<br>ny vei?", "Går du bare de samme veiene, vokser ikke kartet"),
    ],
    "id": [
        ("01-map.png",      "hero-bleed",  "Peta kosong yang hanya menyimpan<br>langkahmu", "Perjalanan dengan mobil tidak digambar"),
        ("02-compass.png",  "left-text",   "Hari ini<br>ke arah mana?", "Kompas menunjuk arah yang paling sedikit kamu jalani"),
        ("03-stamps.png",   "text-bottom", "Stempel untuk tempat yang dikunjungi dan dituju", "Catat lingkunganmu dengan 212 stempel"),
        ("04-calendar.png", "flat-rotate", "Setiap hari,<br>seperti yang kamu jalani", "Kalender menyimpan jalan hari itu, bukan angka"),
        ("05-diary.png",    "dark",        "Berapa banyak<br>jalan baru?", "Jika hanya menyusuri jalan yang sama, peta tidak bertambah luas"),
    ],
    "fi": [
        ("01-map.png",      "hero-bleed",  "Tyhjä kartta, joka säilyttää<br>vain askeleesi", "Autolla kuljettuja teitä ei piirretä"),
        ("02-compass.png",  "left-text",   "Tänään<br>mihin suuntaan?", "Kompassi osoittaa, missä olet kulkenut vähiten"),
        ("03-stamps.png",   "text-bottom", "Leimat käydyille ja käytäville paikoille", "Tallenna naapurustosi 212 leimalla"),
        ("04-calendar.png", "flat-rotate", "Jokainen päivä<br>sellaisena kuin kävelit", "Kalenteriin jää päivän tie numeron sijaan"),
        ("05-diary.png",    "dark",        "Kuinka paljon oli<br>uutta tietä?", "Jos kävelet vain samoja teitä, kartta ei kasva"),
    ],
    "el": [
        ("01-map.png",      "hero-bleed",  "Ένας λευκός χάρτης που κρατά<br>μόνο τα βήματά σας", "Οι διαδρομές με αυτοκίνητο δεν σχεδιάζονται"),
        ("02-compass.png",  "left-text",   "Σήμερα<br>προς τα πού;", "Η πυξίδα δείχνει όπου έχετε περπατήσει λιγότερο"),
        ("03-stamps.png",   "text-bottom", "Σφραγίδες για μέρη που πήγατε και θέλετε να πάτε", "Καταγράψτε τη γειτονιά σας με 212 σφραγίδες"),
        ("04-calendar.png", "flat-rotate", "Κάθε μέρα<br>όπως την περπατήσατε", "Το ημερολόγιο κρατά τη διαδρομή της μέρας αντί για αριθμό"),
        ("05-diary.png",    "dark",        "Πόσο ήταν<br>νέος δρόμος;", "Αν περπατάτε μόνο τους ίδιους δρόμους, ο χάρτης δεν μεγαλώνει"),
    ],
    "da": [
        ("01-map.png",      "hero-bleed",  "Et tomt kort, der kun gemmer<br>dine skridt", "Veje i bil tegnes ikke"),
        ("02-compass.png",  "left-text",   "I dag<br>hvilken vej?", "Kompasset peger mod der, hvor du har gået mindst"),
        ("03-stamps.png",   "text-bottom", "Stempler til besøgte steder og mål", "Registrér dit kvarter med 212 stempler"),
        ("04-calendar.png", "flat-rotate", "Hver dag<br>præcis som du gik den", "Kalenderen gemmer dagens vej i stedet for et tal"),
        ("05-diary.png",    "dark",        "Hvor meget var<br>en ny vej?", "Går du kun de samme veje, vokser kortet ikke"),
    ],
    "cs": [
        ("01-map.png",      "hero-bleed",  "Prázdná mapa, která drží<br>jen tvé kroky", "Cesty autem se nekreslí"),
        ("02-compass.png",  "left-text",   "Kam se dnes<br>vydat?", "Kompas ukazuje, kudy jsi chodil nejméně"),
        ("03-stamps.png",   "text-bottom", "Razítka pro navštívená místa i cíle", "Zaznamenej svou čtvrť pomocí 212 razítek"),
        ("04-calendar.png", "flat-rotate", "Každý den<br>tak, jak jsi ho prošel", "Kalendář uchová cestu dne místo čísla"),
        ("05-diary.png",    "dark",        "Kolik z toho<br>byla nová cesta?", "Když chodíš jen po stejných cestách, mapa neroste"),
    ],
    "vi": [
        ("01-map.png",      "hero-bleed",  "Bản đồ trắng chỉ giữ lại<br>những bước chân của bạn", "Đường đi bằng ô tô không được vẽ"),
        ("02-compass.png",  "left-text",   "Hôm nay<br>đi hướng nào?", "La bàn chỉ hướng bạn đi ít nhất"),
        ("03-stamps.png",   "text-bottom", "Đóng dấu nơi đã tới và muốn tới", "Ghi lại khu phố của bạn với 212 con dấu"),
        ("04-calendar.png", "flat-rotate", "Mỗi ngày<br>đúng như bạn đã đi", "Lịch giữ lại con đường của ngày đó thay vì con số"),
        ("05-diary.png",    "dark",        "Bao nhiêu trong đó<br>là đường mới?", "Chỉ đi lại những đường cũ thì bản đồ không lớn lên"),
    ],
    "th": [
        ("01-map.png",      "hero-bleed",  "แผนที่เปล่าที่เก็บไว้<br>เฉพาะก้าวเดินของคุณ", "เส้นทางที่ผ่านด้วยรถจะไม่ถูกวาด"),
        ("02-compass.png",  "left-text",   "วันนี้<br>ไปทางไหนดี", "เข็มทิศชี้ทิศที่เดินน้อยที่สุด"),
        ("03-stamps.png",   "text-bottom", "ประทับตราที่ที่ไปมาแล้วและที่อยากไป", "บันทึกย่านของคุณด้วยตราประทับ 212 แบบ"),
        ("04-calendar.png", "flat-rotate", "ทุกวัน<br>ตามรูปร่างที่เดิน", "ปฏิทินเก็บเส้นทางของวันนั้นแทนตัวเลข"),
        ("05-diary.png",    "dark",        "ทางใหม่<br>มีสักเท่าไร", "เดินแต่ทางเดิมก็ไม่ทำให้แผนที่โตขึ้น"),
    ],
    "ru": [
        ("01-map.png",      "hero-bleed",  "Чистая карта, хранящая<br>только ваши шаги", "Поездки на машине не рисуются"),
        ("02-compass.png",  "left-text",   "Сегодня<br>в какую сторону?", "Компас показывает, где вы ходили меньше всего"),
        ("03-stamps.png",   "text-bottom", "Штампы для посещённых мест и мест, куда хочется", "Ведите запись своего района с 212 штампами"),
        ("04-calendar.png", "flat-rotate", "Каждый день<br>таким, каким вы его прошли", "В календаре не число, а путь этого дня"),
        ("05-diary.png",    "dark",        "Сколько из пройденного<br>было новым?", "Если ходить по одним и тем же путям, карта не растёт"),
    ],
    "pt-BR": [
        ("01-map.png",      "hero-bleed",  "Um mapa em branco que guarda<br>só os seus passos", "Trajetos de carro não são desenhados"),
        ("02-compass.png",  "left-text",   "Hoje,<br>para que lado?", "A bússola aponta onde você menos caminhou"),
        ("03-stamps.png",   "text-bottom", "Carimbos para lugares visitados e para visitar", "Registre seu bairro com 212 carimbos"),
        ("04-calendar.png", "flat-rotate", "Cada dia,<br>do jeito que você andou", "O calendário guarda o caminho do dia, não um número"),
        ("05-diary.png",    "dark",        "Quanto foi<br>caminho novo?", "Repetindo sempre os mesmos caminhos, o mapa não cresce"),
    ],
    "it": [
        ("01-map.png",      "hero-bleed",  "Una mappa bianca che tiene<br>solo i tuoi passi", "I tragitti in auto non vengono disegnati"),
        ("02-compass.png",  "left-text",   "Oggi<br>da che parte?", "La bussola indica dove hai camminato meno"),
        ("03-stamps.png",   "text-bottom", "Timbri per i luoghi visitati e da visitare", "Racconta il tuo quartiere con 212 timbri"),
        ("04-calendar.png", "flat-rotate", "Ogni giorno,<br>com’è stato camminato", "Il calendario conserva il percorso del giorno, non un numero"),
        ("05-diary.png",    "dark",        "Quanta strada<br>era nuova?", "Rifacendo sempre le stesse strade la mappa non cresce"),
    ],
    "fr": [
        ("01-map.png",      "hero-bleed",  "Une carte blanche qui ne garde<br>que vos pas", "Les trajets en voiture ne sont pas dessinés"),
        ("02-compass.png",  "left-text",   "Aujourd’hui,<br>de quel côté ?", "La boussole indique où vous avez le moins marché"),
        ("03-stamps.png",   "text-bottom", "Des tampons pour les lieux visités et à visiter", "Racontez votre quartier avec 212 tampons"),
        ("04-calendar.png", "flat-rotate", "Chaque jour,<br>tel que vous l’avez marché", "Le calendrier garde le chemin du jour, pas un chiffre"),
        ("05-diary.png",    "dark",        "Quelle part<br>de nouveaux chemins ?", "À refaire les mêmes chemins, la carte ne grandit pas"),
    ],
    "de": [
        ("01-map.png",      "hero-bleed",  "Eine leere Karte, die nur<br>deine Wege behält", "Wege mit dem Auto werden nicht gezeichnet"),
        ("02-compass.png",  "left-text",   "Heute<br>in welche Richtung?", "Der Kompass zeigt, wo du am wenigsten warst"),
        ("03-stamps.png",   "text-bottom", "Stempel für besuchte und geplante Orte", "Halte dein Viertel mit 212 Stempeln fest"),
        ("04-calendar.png", "flat-rotate", "Jeder Tag,<br>so wie du ihn gegangen bist", "Der Kalender zeigt den Weg des Tages statt einer Zahl"),
        ("05-diary.png",    "dark",        "Wie viel war<br>ein neuer Weg?", "Wer nur dieselben Wege geht, lässt die Karte nicht wachsen"),
    ],
    "es": [
        ("01-map.png",      "hero-bleed",  "Un mapa en blanco que guarda<br>solo lo que has caminado", "Los caminos en coche no se dibujan"),
        ("02-compass.png",  "left-text",   "¿Hacia dónde<br>hoy?", "La brújula señala la dirección menos caminada"),
        ("03-stamps.png",   "text-bottom", "Sellos para donde fuiste y donde irás", "Registra tu barrio con 212 sellos"),
        ("04-calendar.png", "flat-rotate", "Cada día,<br>tal como lo caminaste", "El calendario guarda el camino del día, no un número"),
        ("05-diary.png",    "dark",        "¿Cuánto fue<br>camino nuevo?", "Si solo repites caminos, el mapa no crece"),
    ],
    "zh-Hant": [
        ("01-map.png",      "hero-bleed",  "只留下親腳走過的路<br>的白地圖", "搭車經過的路不會被畫出"),
        ("02-compass.png",  "left-text",   "今天<br>往哪邊走？", "羅盤指向你走得最少的方向"),
        ("03-stamps.png",   "text-bottom", "為去過和想去的地方蓋章", "用212種印章記錄你的社區"),
        ("04-calendar.png", "flat-rotate", "每一天<br>都是走過的樣子", "月曆上留下的是當天的路，而不是數字"),
        ("05-diary.png",    "dark",        "第一次走的路<br>有多長？", "總走同一條路，地圖是不會變大的"),
    ],
    "zh-Hans": [
        ("01-map.png",      "hero-bleed",  "只留下亲脚走过的路<br>的白地图", "乘车经过的路不会被画出"),
        ("02-compass.png",  "left-text",   "今天<br>往哪边走？", "罗盘指向你走得最少的方向"),
        ("03-stamps.png",   "text-bottom", "给去过和想去的地方盖章", "用212种图章记录你的街区"),
        ("04-calendar.png", "flat-rotate", "每一天<br>都是走过的样子", "日历上留下的是当天的路，而不是数字"),
        ("05-diary.png",    "dark",        "第一次走的路<br>有多长？", "总走同一条路，地图是不会变大的"),
    ],
    "ja": [
        ("01-map.png",      "hero-bleed",  "自分の足で通った道だけが<br>残る白地図", "車で通った道は描かれません"),
        ("02-compass.png",  "left-text",   "今日は<br>どちらへ？", "あまり歩いていない方向をコンパスが指します"),
        ("03-stamps.png",   "text-bottom", "行った場所、行きたい場所にスタンプ", "212種類のスタンプで街を記録します"),
        ("04-calendar.png", "flat-rotate", "毎日<br>歩いた形のまま", "カレンダーには数字の代わりにその日の道が残ります"),
        ("05-diary.png",    "dark",        "はじめての道は<br>どれだけだった？", "同じ道ばかり歩いても地図は育ちません"),
    ],
    "en-GB": [
        ("01-map.png",      "hero-bleed",  "A blank map that keeps<br>only where you've walked", "Roads passed by car aren't drawn"),
        ("02-compass.png",  "left-text",   "Which way<br>today?", "The compass points to where you've walked least"),
        ("03-stamps.png",   "text-bottom", "Stamps for places visited<br>and places to visit", "Record your neighbourhood with 212 stamps"),
        ("04-calendar.png", "flat-rotate", "Every day,<br>just as you walked it", "The calendar keeps each day's path, not a number"),
        ("05-diary.png",    "dark",        "How much of it<br>was a new path?", "Walk only the same roads and the map won't grow"),
    ],
    "en": [
        ("01-map.png",      "hero-bleed",  "A blank map that keeps<br>only where you've walked", "Roads passed by car aren't drawn"),
        ("02-compass.png",  "left-text",   "Which way<br>today?", "The compass points to where you've walked least"),
        ("03-stamps.png",   "text-bottom", "Stamps for places visited<br>and places to visit", "Record your neighborhood with 212 stamps"),
        ("04-calendar.png", "flat-rotate", "Every day,<br>just as you walked it", "The calendar keeps each day's path, not a number"),
        ("05-diary.png",    "dark",        "How much of it<br>was a new path?", "Walk only the same roads and the map won't grow"),
    ],
}
# ─────────────────────────────────────────────────────────────────

BASE_CSS = f"""
* {{ margin:0; padding:0; box-sizing:border-box; }}
html,body {{ width:{W}px; height:{H}px; overflow:hidden; }}
body {{ background:{BG}; position:relative;
  font-family:-apple-system, "SF Pro Display", "Apple SD Gothic Neo", "Hiragino Sans", "PingFang SC", sans-serif; }}
.headline {{ font-size:96px; font-weight:800; color:{INK}; letter-spacing:-0.03em; line-height:1.18; }}
.sub {{ font-size:48px; font-weight:500; color:{SUB}; letter-spacing:-0.01em; line-height:1.35; }}
:lang(ko) .headline, :lang(ko) .sub {{ word-break:keep-all; }}
.phone {{ background:#17171a; border-radius:112px; border:3px solid #3a3a3e; padding:24px;
  box-shadow: 50px 80px 120px rgba(20,40,90,.25), 16px 26px 46px rgba(0,0,0,.16); }}
.phone img {{ width:100%; display:block; border-radius:90px; }}
.dot {{ display:inline-block; width:22px; height:22px; border-radius:50%; background:{ACCENT}; margin-bottom:46px; }}
"""

LAYOUTS = {
    "hero-bleed": """
.text { text-align:center; padding:250px 80px 0; }
.sub { margin-top:44px; }
.wrap { display:flex; justify-content:center; margin-top:120px; }
.phone { width:960px; }
""",
    "left-text": """
.text { text-align:left; padding:260px 100px 0 110px; }
.sub { margin-top:44px; }
.wrap { perspective:2600px; perspective-origin:30% 30%; position:absolute; left:290px; top:930px; }
.phone { width:820px; transform:rotateY(16deg) rotateX(2deg); }
""",
    "text-bottom": """
.wrap { perspective:2800px; perspective-origin:50% 40%; display:flex; justify-content:center; margin-top:150px; }
.phone { width:840px; transform:rotateY(-10deg) rotateX(2deg); }
.text { text-align:center; padding:100px 80px 0; }
.sub { margin-top:40px; }
""",
    "flat-rotate": """
.text { text-align:center; padding:240px 80px 0; }
.sub { margin-top:44px; }
.wrap { position:absolute; left:120px; top:950px; }
.phone { width:960px; transform:rotate(-6deg); }
""",
    "dark": f"""
body {{ background:#131316; }}
.headline {{ color:#f5f5f7; }} .sub {{ color:#8a8a90; }}
.text {{ text-align:center; padding:250px 80px 0; }}
.sub {{ margin-top:44px; }}
.wrap {{ display:flex; justify-content:center; margin-top:120px; }}
.phone {{ width:900px; border-color:#48484e;
  box-shadow: 0 0 160px rgba(80,140,255,.22), 40px 70px 110px rgba(0,0,0,.55); }}
""",
}

TEXT = '<div class="text"><div class="dot"></div><div class="headline">{headline}</div><div class="sub">{sub}</div></div>'
PHONE = '<div class="wrap"><div class="phone"><img src="{img}"></div></div>'
HTML = '<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>{css}</style></head><body>{body}</body></html>'


def chrome_shot(html, png, tmp):
    """헤드리스 Chrome 으로 한 장 그린다.

    ⚠️ Chrome 은 그림을 다 쓰고도 끝나지 않고 멈추는 일이 잦다(여러 개가 동시에 돌 때 특히).
       그래서 끝나기를 기다리지 않고, 파일이 생겨 크기가 멈추면 프로세스를 닫는다.
    """
    png.unlink(missing_ok=True)
    proc = subprocess.Popen([CHROME, "--headless=new", f"--user-data-dir={tmp}/chrome", "--no-first-run",
                             "--disable-component-update", "--no-default-browser-check", "--disable-extensions",
                             f"--screenshot={png}", f"--window-size={W},{H}", "--force-device-scale-factor=1",
                             "--hide-scrollbars", "--allow-file-access-from-files", html.as_uri()],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    last, deadline = -1, time.time() + 180
    try:
        while time.time() < deadline:
            time.sleep(1)
            size = png.stat().st_size if png.exists() else -1
            if size > 10000 and size == last:
                return True
            last = size
            if proc.poll() is not None and size <= 0:
                return False
        return False
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.wait()
        # 남은 도우미 프로세스도 이 프로필 것만 골라 닫는다
        subprocess.run(["pkill", "-f", f"{tmp}/chrome"], capture_output=True)


def render(lang):
    out_dir = OUT / STORE[lang]
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("*.png"):
        old.unlink()
    with tempfile.TemporaryDirectory() as tmp:
        for fname, layout, headline, sub in SHOTS[lang]:
            src = RAW / lang / fname
            assert src.exists(), f"원본이 없다: {src}"
            text = TEXT.format(headline=headline, sub=sub)
            phone = PHONE.format(img=src.as_uri())
            body = phone + text if layout == "text-bottom" else text + phone
            html = pathlib.Path(tmp) / f"{lang}-{fname}.html"
            html.write_text(HTML.format(lang=lang, css=BASE_CSS + LAYOUTS[layout], body=body), encoding="utf-8")
            png = out_dir / fname
            if not any(chrome_shot(html, png, tmp) for _ in range(3)):
                raise SystemExit(f"그리지 못했다: {png}")
            print("rendered", png.relative_to(ROOT))


if __name__ == "__main__":
    for lang in (sys.argv[1:] or list(SHOTS)):
        render(lang)
