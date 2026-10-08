// PROTOTYPE — throwaway. The reacting dot grid on the trackpad, three ways, plus the restyled sheet.
// Nothing is sent anywhere: touches only drive the drawing.

const VARIANTS = { A: 'Glow', B: 'Grow', C: 'Repel' };
const DEFAULTS = { sp: 22, sz: 1.1, r: 110, k: 1, dk: 350, base: 0.22, col: 'accent', rip: 1 };
const TUNE = [
  // key, label, min, max, step
  ['sp', 'Spacing', 12, 40, 1],
  ['sz', 'Dot size', 0.5, 2.5, 0.1],
  ['r', 'Reach', 40, 240, 5],
  ['k', 'Strength', 0.2, 3, 0.1],
  ['dk', 'Decay ms', 60, 1500, 10],
  ['base', 'Idle dots', 0, 0.6, 0.02],
];
const ACCENT = [10, 132, 255];
const WHITE = [235, 235, 245];

// ---------- URL state: variant and tuning, so a reload or a shared link keeps them ----------
const url = new URL(location.href);
let variant = VARIANTS[url.searchParams.get('variant')] ? url.searchParams.get('variant') : 'A';
const p = { ...DEFAULTS };
for (const key of Object.keys(DEFAULTS)) {
  const v = url.searchParams.get(key);
  if (v !== null) p[key] = key === 'col' ? v : Number(v);
}
function saveUrl() {
  url.searchParams.set('variant', variant);
  for (const key of Object.keys(DEFAULTS)) url.searchParams.set(key, p[key]);
  history.replaceState(null, '', url);
}

// ---------- The grid ----------
const pad = document.getElementById('pad');
const canvas = document.getElementById('dots');
const ctx = canvas.getContext('2d');
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
let W = 0, H = 0, dpr = 1;
let dots = []; // { x, y, e, w, ox, oy, vx, vy }: e decays after the finger, w is the passing ripple
let effectOn = true;
let connected = true;
let dragging = false;
let touches = []; // { id, x, y } in pad coordinates
let ripples = []; // { x, y, t0, accent }

function layout() {
  const box = pad.getBoundingClientRect();
  dpr = devicePixelRatio || 1;
  W = box.width; H = box.height;
  canvas.width = Math.round(W * dpr);
  canvas.height = Math.round(H * dpr);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  const cols = Math.max(1, Math.floor(W / p.sp));
  const rows = Math.max(1, Math.floor(H / p.sp));
  const x0 = (W - (cols - 1) * p.sp) / 2, y0 = (H - (rows - 1) * p.sp) / 2;
  dots = [];
  for (let j = 0; j < rows; j++) {
    for (let i = 0; i < cols; i++) dots.push({ x: x0 + i * p.sp, y: y0 + j * p.sp, e: 0, w: 0, ox: 0, oy: 0, vx: 0, vy: 0 });
  }
  wake();
}
new ResizeObserver(layout).observe(pad);

const smooth = (t) => (t <= 0 ? 0 : t >= 1 ? 1 : t * t * (3 - 2 * t));
const mix = (a, b, t) => a.map((v, i) => Math.round(v + (b[i] - v) * t));

let running = false, last = 0, frames = 0, fps = 0, fpsAt = 0;
function wake() {
  if (running) return;
  running = true;
  last = performance.now();
  requestAnimationFrame(frame);
}

function frame(now) {
  const dt = Math.min(now - last, 34); // ms
  last = now;
  frames++;
  if (now - fpsAt > 500) { fps = Math.round((frames * 1000) / (now - fpsAt)); frames = 0; fpsAt = now; }
  const busy = step(dt, now);
  draw();
  renderState();
  if (busy) requestAnimationFrame(frame);
  else running = false;
}

/** Moves every dot on by dt; returns whether anything is still moving. */
function step(dt, now) {
  const still = reducedMotion.matches;
  const decay = Math.exp(-dt / p.dk);
  const life = 700, speed = 0.9; // ripple: ms, px/ms
  ripples = ripples.filter((r) => now - r.t0 < life);
  const s = dt / 1000;
  const omega = 9 * Math.sqrt(350 / p.dk), zeta = 0.55; // Repel's spring
  let busy = touches.length > 0 || ripples.length > 0;
  for (const d of dots) {
    let target = 0, wave = 0, tx = 0, ty = 0;
    if (!still) {
      for (const t of touches) {
        const dx = d.x - t.x, dy = d.y - t.y, dist = Math.hypot(dx, dy);
        const f = smooth(1 - dist / p.r);
        if (f > target) target = f;
        if (variant === 'C' && dist > 0.01) { tx += (dx / dist) * f * 16 * p.k; ty += (dy / dist) * f * 16 * p.k; }
      }
      for (const r of ripples) {
        const age = now - r.t0;
        const dist = Math.hypot(d.x - r.x, d.y - r.y);
        const bump = Math.exp(-(((dist - age * speed) / 16) ** 2)) * (1 - age / life);
        if (bump > wave) wave = bump;
        if (variant === 'C' && dist > 0.01) { tx += ((d.x - r.x) / dist) * bump * 6 * p.k; ty += ((d.y - r.y) / dist) * bump * 6 * p.k; }
      }
    }
    d.e = Math.max(target, d.e * decay);
    if (d.e < 0.003) d.e = 0; else busy = true;
    d.w = wave;
    if (variant === 'C') {
      d.vx += (omega * omega * (tx - d.ox) - 2 * zeta * omega * d.vx) * s;
      d.vy += (omega * omega * (ty - d.oy) - 2 * zeta * omega * d.vy) * s;
      d.ox += d.vx * s; d.oy += d.vy * s;
      if (Math.abs(d.ox) + Math.abs(d.oy) + Math.abs(d.vx) + Math.abs(d.vy) > 0.05) busy = true;
      else d.ox = d.oy = d.vx = d.vy = 0;
    } else {
      d.ox = d.oy = d.vx = d.vy = 0;
    }
  }
  return busy;
}

function draw() {
  ctx.clearRect(0, 0, W, H);
  if (!effectOn) return;
  const dim = connected ? 1 : 0.35;
  const tint = !connected ? WHITE : dragging ? ACCENT : p.col === 'white' ? WHITE : ACCENT;
  const two = Math.PI * 2;

  // Idle dots in one path.
  ctx.fillStyle = `rgba(${WHITE.join(',')},${p.base * dim})`;
  ctx.beginPath();
  for (const d of dots) {
    if (d.e > 0 || d.w > 0.01 || d.ox || d.oy) continue;
    ctx.moveTo(d.x + p.sz, d.y);
    ctx.arc(d.x, d.y, p.sz, 0, two);
  }
  ctx.fill();

  // Lit dots one by one.
  for (const d of dots) {
    if (!(d.e > 0 || d.w > 0.01 || d.ox || d.oy)) continue;
    const e = Math.max(d.e, d.w);
    const colour = p.col === 'mix' && !dragging ? mix(WHITE, ACCENT, e * 0.5) : mix(WHITE, tint, e);
    let radius = p.sz, alpha = p.base + (1 - p.base) * e;
    if (variant === 'A') radius = p.sz * (1 + 0.5 * e);
    if (variant === 'B') { radius = p.sz * (1 + 3 * p.k * e); alpha = p.base + (0.9 - p.base) * e; }
    if (variant === 'C') { radius = p.sz * (1 + 0.6 * e); alpha = p.base + (0.85 - p.base) * e; }
    const x = d.x + d.ox, y = d.y + d.oy;
    if (variant === 'A' && e > 0.15) {
      // Bloom: a soft halo behind the brightest dots.
      ctx.fillStyle = `rgba(${colour.join(',')},${0.16 * e * p.k * dim})`;
      ctx.beginPath();
      ctx.arc(x, y, p.sz * 5, 0, two);
      ctx.fill();
    }
    ctx.fillStyle = `rgba(${colour.join(',')},${Math.min(1, alpha * (variant === 'A' ? Math.min(1.4, p.k) : 1)) * dim})`;
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, two);
    ctx.fill();
  }
}

// ---------- Touches: drag after a still hold, ripple on a tap (a click) ----------
let gesture = null; // { t0, x0, y0, moved, max }
let holdTimer = 0;
const local = (t) => {
  const box = pad.getBoundingClientRect();
  return { id: t.identifier, x: t.clientX - box.left, y: t.clientY - box.top };
};
function onTouch(e) {
  e.preventDefault();
  touches = Array.from(e.targetTouches, local);
  if (e.type === 'touchstart') {
    if (!gesture) {
      gesture = { t0: e.timeStamp, x0: touches[0].x, y0: touches[0].y, moved: false, max: 0 };
      holdTimer = setTimeout(() => {
        if (gesture && !gesture.moved && touches.length === 1) { dragging = true; pad.classList.add('drag'); wake(); }
      }, 350);
    }
    gesture.max = Math.max(gesture.max, touches.length);
  }
  if (e.type === 'touchmove' && gesture && touches[0] && Math.hypot(touches[0].x - gesture.x0, touches[0].y - gesture.y0) > 8) {
    gesture.moved = true;
  }
  if ((e.type === 'touchend' || e.type === 'touchcancel') && touches.length === 0 && gesture) {
    clearTimeout(holdTimer);
    if (p.rip && !gesture.moved && !dragging && e.timeStamp - gesture.t0 < 200) {
      const t = local(e.changedTouches[0]);
      ripples.push({ x: t.x, y: t.y, t0: performance.now() });
    }
    gesture = null;
    dragging = false;
    pad.classList.remove('drag');
  }
  wake();
}
for (const type of ['touchstart', 'touchmove', 'touchend', 'touchcancel']) pad.addEventListener(type, onTouch, { passive: false });

const strip = document.getElementById('strip');
strip.addEventListener('touchstart', (e) => { e.preventDefault(); strip.classList.add('on'); }, { passive: false });
for (const type of ['touchend', 'touchcancel']) strip.addEventListener(type, () => strip.classList.remove('on'));

for (const b of document.querySelectorAll('.modes button')) {
  b.addEventListener('click', () => {
    for (const o of document.querySelectorAll('.modes button')) o.classList.toggle('on', o === b);
  });
}

// ---------- Settings sheet ----------
const sheet = document.getElementById('sheet');
const fillRange = (input) => input.style.setProperty('--p', `${((input.value - input.min) / (input.max - input.min)) * 100}%`);
/** Buttons on the pad act on touch-up and keep their touches from the pad. */
function padButton(el, act) {
  el.addEventListener('touchstart', (e) => e.stopPropagation());
  el.addEventListener('touchend', (e) => { e.stopPropagation(); e.preventDefault(); act(); });
  el.addEventListener('click', act);
}
padButton(document.getElementById('gear'), () => sheet.showModal());
const conn = document.getElementById('conn');
padButton(conn, () => {
  connected = !connected;
  conn.classList.toggle('on', connected);
  wake();
});
sheet.addEventListener('click', (e) => { if (e.target === sheet) sheet.close(); });
for (const input of sheet.querySelectorAll('input[type=range]')) {
  fillRange(input);
  input.addEventListener('input', () => { fillRange(input); input.closest('.row').querySelector('output').textContent = input.value; });
}
for (const seg of sheet.querySelectorAll('.seg')) {
  for (const b of seg.children) b.addEventListener('click', () => { for (const o of seg.children) o.classList.toggle('on', o === b); });
}
document.getElementById('effect-switch').addEventListener('change', (e) => { effectOn = e.target.checked; wake(); });

// ---------- Prototype chrome ----------
const keys = Object.keys(VARIANTS);
const label = document.getElementById('label');
const state = document.getElementById('state');
function setVariant(v) {
  variant = v;
  label.textContent = `${v} · ${VARIANTS[v]}`;
  for (const d of dots) { d.ox = d.oy = d.vx = d.vy = 0; }
  saveUrl();
  wake();
}
const cycle = (by) => setVariant(keys[(keys.indexOf(variant) + by + keys.length) % keys.length]);
document.getElementById('prev').addEventListener('click', () => cycle(-1));
document.getElementById('next').addEventListener('click', () => cycle(1));
addEventListener('keydown', (e) => {
  if (e.target.closest('input, textarea, [contenteditable]')) return;
  if (e.key === 'ArrowLeft') cycle(-1);
  if (e.key === 'ArrowRight') cycle(1);
});

let stateText = '';
function renderState() {
  const text = [
    `touches ${touches.length}`,
    dragging ? 'drag' : null,
    connected ? null : 'offline',
    `${dots.length} dots`,
    running ? `${fps} fps` : 'idle',
  ].filter(Boolean).join(' · ');
  if (text !== stateText) state.textContent = stateText = text;
}

const tune = document.getElementById('tune');
document.getElementById('tune-btn').addEventListener('click', () => { tune.hidden = !tune.hidden; });
function renderTune() {
  tune.replaceChildren();
  for (const [key, text, min, max, stepBy] of TUNE) {
    const row = document.createElement('div');
    row.className = 't';
    row.innerHTML = `<span>${text}</span><input type="range" min="${min}" max="${max}" step="${stepBy}"><output></output>`;
    const input = row.querySelector('input'), out = row.querySelector('output');
    input.value = p[key];
    out.textContent = p[key];
    fillRange(input);
    input.addEventListener('input', () => {
      p[key] = Number(input.value);
      out.textContent = input.value;
      fillRange(input);
      saveUrl();
      if (key === 'sp') layout(); else wake();
    });
    tune.append(row);
  }
  const options = (text, key, values) => {
    const row = document.createElement('div');
    row.className = 't';
    row.innerHTML = `<span>${text}</span><div class="opts" style="grid-column: span 2">${values.map(([v, t]) => `<button data-v="${v}">${t}</button>`).join('')}</div>`;
    for (const b of row.querySelectorAll('button')) {
      b.classList.toggle('on', String(p[key]) === b.dataset.v);
      b.addEventListener('click', () => {
        p[key] = key === 'rip' ? Number(b.dataset.v) : b.dataset.v;
        saveUrl();
        renderTune();
        wake();
      });
    }
    tune.append(row);
  };
  options('Colour', 'col', [['accent', 'Blue'], ['white', 'White'], ['mix', 'Mix']]);
  options('Tap ripple', 'rip', [[1, 'On'], [0, 'Off']]);
  const actions = document.createElement('div');
  actions.className = 'actions';
  actions.innerHTML = '<button data-a="reset">Reset</button><button data-a="copy">Copy values</button>';
  actions.querySelector('[data-a=reset]').addEventListener('click', () => {
    Object.assign(p, DEFAULTS);
    saveUrl();
    renderTune();
    layout();
  });
  actions.querySelector('[data-a=copy]').addEventListener('click', async (e) => {
    const text = JSON.stringify({ variant: `${variant} ${VARIANTS[variant]}`, ...p });
    try { await navigator.clipboard.writeText(text); e.target.textContent = 'Copied'; }
    catch { prompt('Copy these values', text); }
    setTimeout(() => { e.target.textContent = 'Copy values'; }, 1200);
  });
  tune.append(actions);
}

renderTune();
setVariant(variant);
