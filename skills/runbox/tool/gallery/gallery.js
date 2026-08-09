/* Run Box client.
 *
 * Reads live data from the local service instead of carrying it inline. Frame
 * locking is meaningful only because runs are deterministic: physics pinned to
 * 60Hz, RNG seeded, input from a tape. Frame N of two runs of the same scenario
 * is the same moment, so a difference on screen is caused by the change under
 * test and nothing else. That is also why comparing runs of DIFFERENT scenarios
 * is refused rather than shown: different tapes are different inputs.
 */
const FPS = 60;
const S = { runs: [], center: 0, slots: { a: null, b: null }, next: "a", frame: 0, playing: false, maxFrames: 1 };

const el = id => document.getElementById(id);
const runOf = id => S.runs.find(r => r.id === id);
const slotVids = () => Array.from(document.querySelectorAll(".slot video"));
const fmt = (v, d = 1) => (v === null || v === undefined) ? "--" : Number(v).toFixed(d);

/* A run's name if it has one, otherwise something recognisable. Never the raw
 * id: it is a timestamp, and nobody can say one out loud or pick it out of a list. */
const nameOf = r => r.label || (r.game + " / " + r.scenario);

/* Physics ticks per step.
 *
 * Stepping one tick through a clip captured every Nth tick lands between
 * recorded frames and the picture does not change, which reads as a broken
 * button. Step by the coarsest stride currently loaded so a step always moves
 * to a frame that exists. */
function stepSize() {
  const loaded = ["a", "b"].map(k => S.slots[k]).filter(Boolean).map(runOf);
  return Math.max(1, ...loaded.map(r => r.captureStride || 1));
}

const EXPORTED = typeof window.__RUNS__ !== "undefined";

async function boot() {
  let runs = [];
  if (EXPORTED) {
    // Baked export: everything is inline, there is no service to ask, and the
    // page must work with the network off.
    runs = window.__RUNS__;
  } else {
    try {
      const res = await fetch("/api/runs");
      runs = await res.json();
    } catch (e) {
      el("stage").innerHTML = '<div class="boot">Service unreachable</div>';
      return;
    }
  }
  // Newest first: the timeline reads top-down as most-recent-first.
  runs.sort((a, b) => String(b.runAt).localeCompare(String(a.runAt)));

  // A run with no clip came from a headless gate, which has no framebuffer by
  // design. Those are pass/fail results, not something to look at, and burying
  // eight reviewable runs among forty-four blank cards makes the carousel
  // useless. They stay in the index and in drift; they just are not shown here.
  S.allRuns = runs;
  const withClips = runs.filter(r => r.clip);
  runs = withClips.length ? withClips : runs;
  S.runs = runs;
  S.hiddenCount = S.allRuns.length - runs.length;
  S.maxFrames = Math.max(1, ...runs.map(r => r.frames || 1));

  el("sub").innerHTML = runs.length + " RUNS WITH CLIPS<br>" +
    new Set(runs.map(r => r.game)).size + " PROTOTYPES" +
    (S.hiddenCount ? " &middot; " + S.hiddenCount + " HEADLESS HIDDEN" : "");
  el("fmax").textContent = String(S.maxFrames).padStart(3, "0");
  el("track").setAttribute("aria-valuemax", S.maxFrames);

  if (!runs.length) {
    el("stage").innerHTML = '<div class="boot">No runs yet &mdash; run harness\\verify.ps1 or capture.ps1</div>';
    paint();
    return;
  }
  buildCards();
  // Open on the two most recent comparable runs, since comparison is the point.
  const first = runs[0];
  const mate = runs.find(r => r.id !== first.id && r.scenario === first.scenario && r.game === first.game);
  S.slots.a = first.id;
  if (mate) S.slots.b = mate.id;
  refresh();
  layout();
  seek(0);
}

/* ---- Cover Flow --------------------------------------------------------- */
function offsetOf(i) {
  const n = S.runs.length;
  let d = i - S.center;
  d = ((d % n) + n) % n;
  if (d > n / 2) d -= n;
  return d;
}

function buildCards() {
  const stage = el("stage");
  stage.innerHTML = "";
  S.runs.forEach((r, i) => {
    const card = document.createElement("div");
    card.className = "card";
    card.dataset.i = i;
    const media = r.clip
      ? '<video muted playsinline preload="metadata" src="' + r.clip + '"></video>'
      : '<span class="noclip">no clip</span>';
    card.innerHTML =
      '<button class="cardbtn" type="button">' + media +
        '<span class="cardmeta">' +
          '<span class="st" style="color:' + (r.passed ? "var(--good)" : "var(--warn)") + ';background:currentColor"></span>' +
          '<span class="lbl">' + nameOf(r) + '</span>' +
          '<span class="in" data-in="' + r.id + '"></span>' +
        '</span>' +
      '</button>';
    card.querySelector(".cardbtn").addEventListener("click", () => {
      if (offsetOf(i) !== 0) { S.center = i; layout(); return; }
      load(r.id);
    });
    const v = card.querySelector("video");
    if (v) v.addEventListener("loadedmetadata", () => { try { v.currentTime = 0.6; } catch (_) {} });
    stage.appendChild(card);
  });
}

function layout() {
  document.querySelectorAll(".card").forEach(card => {
    const d = offsetOf(+card.dataset.i);
    const ad = Math.abs(d);
    const rot = d === 0 ? 0 : (d > 0 ? -58 : 58);
    const z = d === 0 ? 96 : -Math.min(ad, 3) * 62;
    card.style.transform = "translateX(calc(-50% + " + (d * 118) + "px)) translateZ(" + z + "px) rotateY(" + rot + "deg)";
    card.style.opacity = String(Math.max(0, 1 - ad * 0.36));
    card.style.zIndex = String(50 - ad);
    card.style.pointerEvents = ad > 1.6 ? "none" : "auto";
  });
  drawCaption();
  drawInBadges();
}

function spin(dir) {
  if (!S.runs.length) return;
  S.center = ((S.center + dir) % S.runs.length + S.runs.length) % S.runs.length;
  layout();
}

function drawCaption() {
  const r = S.runs[S.center];
  if (!r) { el("caption").textContent = ""; return; }
  const verdict = r.verdict ? '<span class="sep">|</span><span><b>MARKED</b></span>' : "";
  el("caption").innerHTML =
    '<span><b>' + nameOf(r).toUpperCase() + '</b></span><span class="sep">|</span>' +
    '<span class="' + (r.passed ? "ok" : "bad") + '">' + (r.passed ? "PASS" : "FAIL") + '</span><span class="sep">|</span>' +
    '<span>' + (r.frames || 0) + ' FRAMES</span><span class="sep">|</span>' +
    '<span>MEASURED <b>' + fmt(r.measured) + '</b></span><span class="sep">|</span>' +
    '<span>DRIFT <b>' + (r.driftPct === null || r.driftPct === undefined ? "--" : (r.driftPct > 0 ? "+" : "") + fmt(r.driftPct)) + '%</b></span>' +
    verdict;
}

function drawInBadges() {
  document.querySelectorAll(".in").forEach(sp => {
    const id = sp.dataset.in;
    const inA = S.slots.a === id, inB = S.slots.b === id;
    sp.textContent = inA ? "A" : inB ? "B" : "";
    sp.style.background = inA ? "linear-gradient(180deg,#A8F5CE,var(--slotA))"
                        : inB ? "linear-gradient(180deg,#FFE0A0,var(--slotB))" : "transparent";
    sp.style.boxShadow = (inA || inB) ? "inset 0 1px 0 rgba(255,255,255,.6), 0 1px 2px rgba(0,0,0,.6)" : "none";
  });
}

/* ---- slots -------------------------------------------------------------- */
function load(id) {
  if (S.slots.a === id) S.slots.a = null;
  else if (S.slots.b === id) S.slots.b = null;
  else if (!S.slots.a) S.slots.a = id;
  else if (!S.slots.b) S.slots.b = id;
  else { S.slots[S.next] = id; S.next = S.next === "a" ? "b" : "a"; }
  refresh();
}

function refresh() {
  pause();
  drawSlots(); drawDelta(); drawMarkers(); drawInBadges(); drawCaption();
  seek(S.frame);
}

function drawSlot(key) {
  const box = el("slot" + key.toUpperCase());
  const id = S.slots[key];
  const K = key.toUpperCase();
  box.dataset.filled = id ? "true" : "false";
  if (!id) {
    box.innerHTML = '<div class="slot-head"><span class="badge">' + K + '</span>' +
      '<span class="nm" style="color:var(--engrave-lo)">NO DISC</span></div>' +
      '<div class="glass"><div class="slot-empty"><b>+</b><span>load a cover</span></div></div>';
    return;
  }
  const r = runOf(id);
  const media = r.clip
    ? '<video muted playsinline preload="auto" src="' + r.clip + '"></video>'
    : '<div class="slot-empty"><span>no clip captured</span></div>';
  box.innerHTML =
    '<div class="slot-head"><span class="badge">' + K + '</span>' +
      '<span class="nm">' + nameOf(r).toUpperCase() + '</span>' +
      '<span class="vel">' + new Date(r.runAt).toLocaleTimeString() + '</span>' +
      '<button class="eject" type="button" aria-label="Eject">&times;</button></div>' +
    '<div class="glass">' + media + '</div>';
  box.querySelector(".eject").addEventListener("click", () => load(id));
}

function drawSlots() { drawSlot("a"); drawSlot("b"); }

/* Compared client-side when exported, because there is no service to ask. Same
 * refusal rule either way: frame-locking is only meaningful within one scenario. */
function compareLocally(a, b) {
  if (a.game !== b.game || a.scenario !== b.scenario) {
    return { comparable: false, reason: "different scenario: " + a.game + "/" + a.scenario + " vs " + b.game + "/" + b.scenario };
  }
  const count = (r, n) => (r.events || []).filter(e => e.name === n).length;
  const row = (metric, av, bv, dp) => ({
    metric, a: av, b: bv, dp,
    delta: (av === null || av === undefined || bv === null || bv === undefined) ? null : Math.round((bv - av) * 1000) / 1000,
  });
  const rows = [
    row("measured", a.measured, b.measured, 1),
    row("claimed", a.claimed, b.claimed, 1),
    row("frames", a.frames, b.frames, 0),
  ];
  // Whatever kinds these two runs actually emitted, rather than a list of event
  // names baked in for one genre. A shooter records hits and reloads; a
  // platformer records jumps and deaths. The tool should not need to know which.
  for (const kind of eventKinds([a, b])) rows.push(row(kind, count(a, kind), count(b, kind), 0));
  return { comparable: true, rows: rows };
}

/* Distinct event kinds present across the given runs, minus the ones that carry
 * no gameplay meaning. Sorted so the ordering is stable between renders. */
const IGNORED_EVENTS = ["note"];
function eventKinds(runs) {
  const set = new Set();
  runs.forEach(r => (r && r.events ? r.events : []).forEach(e => {
    if (e && e.name && IGNORED_EVENTS.indexOf(e.name) < 0) set.add(e.name);
  }));
  return Array.from(set).sort();
}

async function drawDelta() {
  const A = S.slots.a ? runOf(S.slots.a) : null;
  const B = S.slots.b ? runOf(S.slots.b) : null;
  const host = el("delta");
  if (!A || !B) {
    host.innerHTML = '<table><tbody><tr><td class="empty">Load both screens to compare</td></tr></tbody></table>';
    return;
  }
  if (EXPORTED) {
    renderDelta(host, compareLocally(A, B));
    return;
  }
  let cmp;
  try {
    const res = await fetch("/api/compare?a=" + encodeURIComponent(A.id) + "&b=" + encodeURIComponent(B.id));
    cmp = await res.json();
  } catch (_) {
    host.innerHTML = '<table><tbody><tr><td class="empty">Comparison unavailable</td></tr></tbody></table>';
    return;
  }
  renderDelta(host, cmp);
}

function renderDelta(host, cmp) {
  if (!cmp.comparable) {
    host.innerHTML = '<table><tbody><tr><td class="empty">' + (cmp.reason || "not comparable") + '</td></tr></tbody></table>';
    return;
  }
  let html = '<table><thead><tr><th>Metric</th><th>A</th><th>B</th><th>B &minus; A</th></tr></thead><tbody>';
  cmp.rows.forEach(row => {
    const d = row.delta;
    html += '<tr><td>' + row.metric.toUpperCase() + '</td>' +
            '<td class="va">' + fmt(row.a, row.dp) + '</td>' +
            '<td class="vb">' + fmt(row.b, row.dp) + '</td>' +
            '<td>' + (d === null || d === undefined ? "&mdash;" : (d > 0 ? "+" : "") + fmt(d, row.dp)) + '</td></tr>';
  });
  host.innerHTML = html + '</tbody></table>';
}

/* ---- markers ------------------------------------------------------------ */
function drawMarkers() {
  const track = el("track");
  track.querySelectorAll(".marker").forEach(m => m.remove());

  const loaded = ["a", "b"].map(k => S.slots[k]).filter(Boolean).map(runOf);
  const kinds = eventKinds(loaded);

  [["a", "var(--slotA)"], ["b", "var(--slotB)"]].forEach(([key, hue], li) => {
    const id = S.slots[key];
    if (!id) return;
    const r = runOf(id);
    (r.events || []).forEach(ev => {
      const kindIndex = kinds.indexOf(ev.name);
      if (kindIndex < 0) return;                       // ignored kinds only
      const m = document.createElement("div");
      m.className = "marker";
      // Height encodes the kind so two event types are distinguishable at a
      // glance without the tool knowing what either of them means.
      m.style.height = (11 - Math.min(kindIndex, 3) * 2) + "px";
      m.style.opacity = String(1 - Math.min(kindIndex, 3) * 0.18);
      m.style.left = (ev.frame / S.maxFrames * 100) + "%";
      m.style.top = (3 + li * 12) + "px";
      m.style.background = hue;
      m.style.boxShadow = "0 0 5px " + hue;
      m.title = key.toUpperCase() + " " + ev.name + " @ frame " + ev.frame +
                (ev.x === undefined ? "" : " (x=" + ev.x + ")");
      m.addEventListener("click", e => { e.stopPropagation(); pause(); seek(ev.frame); });
      track.appendChild(m);
    });
  });

  // Legend names whatever this prototype actually records.
  const legend = el("legend");
  if (legend) {
    legend.innerHTML = kinds.map((k, i) =>
      '<span><i style="height:' + (11 - Math.min(i, 3) * 2) + 'px;opacity:' +
      (1 - Math.min(i, 3) * 0.18) + '"></i>' + k.toUpperCase() + '</span>').join("") +
      '<span>Click a marker to seek both screens</span>';
  }
}

/* ---- transport ---------------------------------------------------------- */
function seek(f) {
  S.frame = Math.max(0, Math.min(S.maxFrames, Math.round(f)));
  const t = S.frame / FPS;
  slotVids().forEach(v => { try { v.currentTime = t; } catch (_) {} });
  paint();
}

function paint() {
  const pct = S.maxFrames ? (S.frame / S.maxFrames) : 0;
  el("fill").style.width = "calc(" + (pct * 100) + "% - 4px)";
  el("playhead").style.left = (pct * 100) + "%";
  el("fnum").textContent = String(S.frame).padStart(3, "0");
  el("track").setAttribute("aria-valuenow", S.frame);
  el("play").textContent = S.playing ? "PAUSE" : "PLAY";
  const none = !S.slots.a && !S.slots.b;
  ["play", "back10", "back1", "fwd1", "fwd10"].forEach(i => { el(i).disabled = none; });
  el("swap").disabled = !S.slots.a || !S.slots.b;
  ["a", "b"].forEach(k => {
    const btn = el("mark" + k.toUpperCase());
    const id = S.slots[k];
    btn.disabled = !id;
    const r = id ? runOf(id) : null;
    btn.setAttribute("aria-pressed", r && r.verdict ? "true" : "false");
  });
}

function play() {
  if (!S.slots.a && !S.slots.b) return;
  if (S.frame >= S.maxFrames) seek(0);
  S.playing = true;
  slotVids().forEach(v => v.play().catch(() => {}));
  paint();
  requestAnimationFrame(tick);
}

function pause() { S.playing = false; slotVids().forEach(v => v.pause()); paint(); }

function tick() {
  if (!S.playing) return;
  const vs = slotVids();
  if (!vs.length) { pause(); return; }
  const master = vs[0];
  S.frame = Math.min(S.maxFrames, Math.round(master.currentTime * FPS));
  // Browsers do not hold independent <video> elements in lockstep; nudge any
  // that wanders more than half a frame from the master.
  for (let i = 1; i < vs.length; i++) {
    if (Math.abs(vs[i].currentTime - master.currentTime) > 0.5 / FPS) vs[i].currentTime = master.currentTime;
  }
  paint();
  if (master.ended || S.frame >= S.maxFrames) { pause(); return; }
  requestAnimationFrame(tick);
}

/* ---- verdicts and launch ------------------------------------------------ */
async function toggleMark(key) {
  const id = S.slots[key];
  if (!id) return;
  const r = runOf(id);
  const want = !r.verdict;
  try {
    await fetch("/api/verdict", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: id, liked: want }),
    });
    r.verdict = want ? "liked" : null;
  } catch (_) {}
  paint(); drawCaption();
}

async function launchCentre() {
  const r = S.runs[S.center];
  if (!r) return;
  try {
    const res = await fetch("/api/launch/" + encodeURIComponent(r.game), { method: "POST" });
    const j = await res.json();
    el("caption").innerHTML = res.ok
      ? '<span><b>LAUNCHED ' + r.game.toUpperCase() + '</b> <span class="sep">|</span> PID ' + j.pid + '</span>'
      : '<span class="bad">LAUNCH FAILED: ' + (j.error || res.status) + '</span>';
  } catch (e) {
    el("caption").innerHTML = '<span class="bad">LAUNCH FAILED</span>';
  }
}

/* ---- wiring ------------------------------------------------------------- */
el("prev").addEventListener("click", () => spin(-1));
el("next").addEventListener("click", () => spin(1));
el("play").addEventListener("click", () => S.playing ? pause() : play());
el("back1").addEventListener("click", () => { pause(); seek(S.frame - stepSize()); });
el("fwd1").addEventListener("click", () => { pause(); seek(S.frame + stepSize()); });
el("back10").addEventListener("click", () => { pause(); seek(S.frame - stepSize() * 10); });
el("fwd10").addEventListener("click", () => { pause(); seek(S.frame + stepSize() * 10); });
el("swap").addEventListener("click", () => { const t = S.slots.a; S.slots.a = S.slots.b; S.slots.b = t; refresh(); });
el("markA").addEventListener("click", () => toggleMark("a"));
el("markB").addEventListener("click", () => toggleMark("b"));

el("track").addEventListener("click", e => {
  const b = e.currentTarget.getBoundingClientRect();
  pause(); seek((e.clientX - b.left) / b.width * S.maxFrames);
});
el("track").addEventListener("keydown", e => {
  const d = { ArrowLeft: -1, ArrowRight: 1, PageDown: -10, PageUp: 10 }[e.key];
  if (d === undefined) return;
  e.preventDefault(); pause(); seek(S.frame + d);
});

let wheelLock = 0;
el("stage").addEventListener("wheel", e => {
  e.preventDefault();
  const now = Date.now();
  if (now - wheelLock < 300) return;
  wheelLock = now;
  spin(Math.sign(e.deltaX || e.deltaY));
}, { passive: false });

document.addEventListener("keydown", e => {
  if (e.target === el("track")) return;
  if (e.key === "ArrowLeft") { e.preventDefault(); spin(-1); }
  else if (e.key === "ArrowRight") { e.preventDefault(); spin(1); }
  else if (e.key === " ") { e.preventDefault(); S.playing ? pause() : play(); }
  else if (e.key === "a" || e.key === "A") { const r = S.runs[S.center]; if (r) { S.slots.a = r.id; refresh(); } }
  else if (e.key === "b" || e.key === "B") { const r = S.runs[S.center]; if (r) { S.slots.b = r.id; refresh(); } }
  else if (e.key === "l" || e.key === "L") { launchCentre(); }
});

boot();
