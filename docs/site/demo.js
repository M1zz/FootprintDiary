// 벅뚜벅뚜 웹 데모: 종이 위를 끌어 걸으면 걸은 자리만 점으로 찍히고, 처음 걷는 길만 '오늘 그은 길'에 더해진다.
// 규칙은 앱과 같다 — 점 칸 10m (WalkHeatmap.cellMeters), 경로 점 간격 12m (LocationManager.trackPointSpacing),
// 같은 길 판정 30m 칸과 그 이웃 (WalkNovelty.sameRoadCell), 빛깔은 DotPalette(오늘 주묵 · 지난 걸음 남빛 · 석 달 넘으면 잿빛).
(() => {
  const root = document.getElementById("demo");
  if (!root) return;
  const T = JSON.parse(root.dataset.text);
  const W = 600, H = 380, CELL = 10, STEP = 12, SAME = 30;   // 종이 한 장 = 600m × 380m

  root.innerHTML = `
    <div class="bk-stats" aria-live="polite">
      <div><b class="bk-today">+0m</b><span>${T.today}</span></div>
      <div><b class="bk-walked">0m</b><span>${T.walked}</span></div>
    </div>
    <canvas class="bk-paper" tabindex="0" role="application" aria-label="${T.hint}"></canvas>
    <p class="bk-msg">${T.hint}</p>
    <div class="bk-bar">
      <ul class="bk-legend" aria-hidden="true">
        <li><i class="t"></i>${T.legendToday}</li><li><i class="p"></i>${T.legendPast}</li><li><i class="f"></i>${T.legendFaded}</li>
      </ul>
      <span class="bk-space"></span>
      <button type="button" class="bk-btn" data-act="subway" aria-pressed="false">${T.subway}</button>
      <button type="button" class="bk-btn" data-act="reset">${T.reset}</button>
    </div>
    <p class="muted small bk-note">${T.note}</p>`;

  const $ = s => root.querySelector(s);
  const canvas = $(".bk-paper"), ctx = canvas.getContext("2d"), msg = $(".bk-msg");
  const subwayBtn = $('[data-act="subway"]');

  // 예전에 걸은 길(m 좌표): 집에서 역까지 늘 다니는 길, 그리고 석 달 넘게 안 간 공원 길.
  const PAST = [[[60, 300], [60, 200], [220, 200], [220, 90], [400, 90]], [[220, 200], [330, 200], [330, 300]]];
  const FADED = [[[470, 300], [540, 300], [540, 230]]];
  const key = (x, y, s) => `${Math.floor(x / s)},${Math.floor(y / s)}`;

  let past, faded, walkedSame, today, todayNew, walked, pos, subway = false;
  function along(line, fn) {   // 선을 따라 반 칸 간격으로 점을 낸다
    for (let i = 1; i < line.length; i++) {
      const [ax, ay] = line[i - 1], [bx, by] = line[i], n = Math.ceil(Math.hypot(bx - ax, by - ay) / (CELL / 2));
      for (let k = 0; k <= n; k++) fn(ax + (bx - ax) * k / n, ay + (by - ay) * k / n);
    }
  }
  function reset() {
    past = new Map(); faded = new Set(); walkedSame = new Set(); today = new Set();
    todayNew = 0; walked = 0; pos = { x: 60, y: 300 };
    // 지난 횟수는 한 번 지날 때 칸마다 1 (WalkHeatmap.cells). 늘 다니는 길은 여러 번 지났다고 둔다.
    PAST.forEach((l, i) => {
      const touched = new Set();
      along(l, (x, y) => { touched.add(key(x, y, CELL)); walkedSame.add(key(x, y, SAME)); });
      touched.forEach(k => past.set(k, (past.get(k) || 0) + (i ? 2 : 8)));
    });
    FADED.forEach(l => along(l, (x, y) => { faded.add(key(x, y, CELL)); walkedSame.add(key(x, y, SAME)); }));
    say(T.hint); draw();
  }

  // 한 걸음(12m 안쪽)을 내딛는다. 30m 칸과 그 이웃 중 예전에 밟은 칸이 있으면 같은 길이다.
  function step(x, y) {
    x = Math.max(0, Math.min(W - 1, x)); y = Math.max(0, Math.min(H - 1, y));
    const d = Math.hypot(x - pos.x, y - pos.y), from = pos;
    pos = { x, y };
    if (subway) { say(T.ride); return; }
    const [cx, cy] = key(x, y, SAME).split(",").map(Number);
    let same = false;
    for (let i = -1; i <= 1; i++) for (let j = -1; j <= 1; j++) if (walkedSame.has(`${cx + i},${cy + j}`)) same = true;
    walked += d;
    if (!same) todayNew += d;
    say(same ? T.same : T.fresh);
    // 점은 칸마다 하나. 걸음 사이 칸도 빠지지 않게 반 칸 간격으로 채운다.
    const n = Math.max(1, Math.ceil(d / (CELL / 2)));
    for (let k = 0; k <= n; k++) today.add(key(from.x + (x - from.x) * k / n, from.y + (y - from.y) * k / n, CELL));
  }
  function walkTo(x, y) {
    const n = Math.max(1, Math.ceil(Math.hypot(x - pos.x, y - pos.y) / STEP)), sx = pos.x, sy = pos.y;
    for (let k = 1; k <= n; k++) step(sx + (x - sx) * k / n, sy + (y - sy) * k / n);
    draw();
  }
  let lastMsg;
  function say(t) { if (t !== lastMsg) msg.textContent = lastMsg = t; }

  // 그리기: 점은 칸 간격의 84%, 오늘은 꽉 채우고 지난 걸음은 지난 횟수만큼 짙고 굵다.
  const dark = matchMedia("(prefers-color-scheme: dark)");
  function hsv(h, s, v) { const f = n => { const k = (n + h * 6) % 6; return Math.round(255 * (v - v * s * Math.max(0, Math.min(k, 4 - k, 1)))); }; return `${f(5)},${f(3)},${f(1)}`; }
  function draw() {
    const scale = canvas.clientWidth / W, dpr = window.devicePixelRatio || 1;
    canvas.width = canvas.clientWidth * dpr; canvas.height = canvas.clientWidth * H / W * dpr;
    ctx.setTransform(scale * dpr, 0, 0, scale * dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    const dk = dark.matches, r = CELL * 0.42;
    const dot = (k, color, a, grow = 1) => {
      const [i, j] = k.split(",").map(Number);
      ctx.fillStyle = `rgba(${color},${a})`; ctx.beginPath();
      ctx.arc(i * CELL + CELL / 2, j * CELL + CELL / 2, r * grow, 0, 7); ctx.fill();
    };
    const grey = hsv(0, 0, dk ? 0.70 : 0.42);
    faded.forEach(k => { if (!today.has(k)) dot(k, grey, 0.45); });
    past.forEach((n, k) => { if (!today.has(k)) { const heat = Math.min(1, n / 10); dot(k, hsv(0.58, 0.88, dk ? 0.95 : 0.78), Math.min(1, 0.8 + 0.2 * heat), 1 + 0.45 * heat); } });
    today.forEach(k => dot(k, hsv(0.02, 0.88, dk ? 0.95 : 0.78), 1));
    // 지금 선 자리
    ctx.fillStyle = "#fff"; ctx.beginPath(); ctx.arc(pos.x, pos.y, 9, 0, 7); ctx.fill();
    ctx.fillStyle = subway ? "#8a8f94" : `rgb(${hsv(0.02, 0.88, 0.85)})`; ctx.beginPath(); ctx.arc(pos.x, pos.y, 6, 0, 7); ctx.fill();
    $(".bk-today").textContent = `+${Math.round(todayNew)}m`;
    $(".bk-walked").textContent = `${Math.round(walked)}m`;
  }

  const toWorld = e => { const b = canvas.getBoundingClientRect(); return [(e.clientX - b.left) * W / b.width, (e.clientY - b.top) * H / b.height]; };
  let dragging = false;
  canvas.addEventListener("pointerdown", e => {
    if (e.button > 0) return;
    e.preventDefault(); canvas.setPointerCapture(e.pointerId); dragging = true;
    const [x, y] = toWorld(e);
    if (Math.hypot(x - pos.x, y - pos.y) > 40) { pos = { x, y }; draw(); }   // 다른 자리에서 시작하면 그리로 옮겨 서서 걷는다
  });
  canvas.addEventListener("pointermove", e => { if (dragging) walkTo(...toWorld(e)); });
  canvas.addEventListener("pointerup", () => { dragging = false; });
  canvas.addEventListener("pointercancel", () => { dragging = false; });
  canvas.addEventListener("keydown", e => {
    const m = { ArrowUp: [0, -1], ArrowDown: [0, 1], ArrowLeft: [-1, 0], ArrowRight: [1, 0] }[e.key];
    if (!m) return;
    e.preventDefault();
    walkTo(pos.x + m[0] * STEP, pos.y + m[1] * STEP);
  });
  root.addEventListener("click", e => {
    const act = e.target.closest("[data-act]")?.dataset.act;
    if (act === "subway") {
      subway = !subway;
      subwayBtn.setAttribute("aria-pressed", String(subway));
      subwayBtn.textContent = subway ? T.subwayOn : T.subway;
      say(subway ? T.ride : T.hint); draw();
    }
    if (act === "reset") { subway = false; subwayBtn.setAttribute("aria-pressed", "false"); subwayBtn.textContent = T.subway; reset(); }
  });
  addEventListener("resize", draw);
  dark.addEventListener?.("change", draw);
  reset();
})();
