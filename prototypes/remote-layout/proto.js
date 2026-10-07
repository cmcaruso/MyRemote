// PROTOTYPE — throwaway, not production. Answers issue #6:
// "What should the Remote's layout and Mode switching look like?"
// Four structurally different variants of the whole Remote, switchable via ?variant=
// and the magenta pill. Nothing reaches the Host; the pill shows what would be sent.

const MODES = ['trackpad', 'keyboard', 'media', 'presentation'];
const NAME = { trackpad: 'Trackpad', keyboard: 'Keyboard', media: 'Media', presentation: 'Presentation' };
const SHORT = { trackpad: 'Trackpad', keyboard: 'Keys', media: 'Media', presentation: 'Present' };

const stroke = d => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
const filled = d => `<svg viewBox="0 0 24 24" fill="currentColor">${d}</svg>`;
const ICON = {
  trackpad: stroke('<rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="12" cy="11" r="2"/>'),
  keyboard: stroke('<rect x="2" y="6" width="20" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M7 14h10"/>'),
  media: stroke('<path d="M8 5v14l11-7z"/>'),
  presentation: stroke('<rect x="3" y="4" width="18" height="12" rx="1"/><path d="M12 16v4M8 20h8"/>'),
  play: filled('<path d="M7 4l13 8-13 8z"/>'),
  pause: filled('<path d="M6 4h4v16H6zM14 4h4v16h-4z"/>'),
  prev: filled('<path d="M5 5h2.5v14H5zM19 5 8.5 12 19 19z"/>'),
  next: filled('<path d="M16.5 5H19v14h-2.5zM5 5l10.5 7L5 19z"/>'),
  speaker: filled('<path d="M3 9h4l5-4v14l-5-4H3z"/>'),
};

const VARIANTS = {
  A: ['Tab bar', VariantA],
  B: ['Swipe pager', VariantB],
  C: ['Thumb hub', VariantC],
  D: ['Split console', VariantD],
};

const params = new URLSearchParams(location.search);
const state = {
  variant: VARIANTS[params.get('variant')] ? params.get('variant') : 'A',
  mode: MODES.includes(params.get('mode')) ? params.get('mode') : 'trackpad',
  last: 'nothing sent yet',
};

function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'class') el.className = v;
    else if (k === 'html') el.innerHTML = v;
    else el.setAttribute(k, v);
  }
  for (const kid of kids.flat()) if (kid != null) el.append(kid);
  return el;
}
const place = (el, x, y) => { el.style.left = `${x}px`; el.style.top = `${y}px`; };
const fmt = n => (n >= 0 ? '+' : '') + Math.round(n);

function send(cmd) { state.last = cmd; renderPill(); }
function setMode(m) { state.mode = m; syncUrl(); renderPill(); }
function syncUrl() { history.replaceState(null, '', `?variant=${state.variant}&mode=${state.mode}`); }

// ---------- shared Mode pieces (the question is layout, so these stay the same across variants) ----------

function trackpad(hint = 'One finger moves · tap clicks · two-finger tap right-clicks · two fingers scroll') {
  const el = h('div', { class: 'pad' }, h('div', { class: 'pad-hint' }, hint));
  const pts = new Map();
  let maxPts = 0, startedAt = 0, travel = 0, raf = 0;
  let acc = { dx: 0, dy: 0, sy: 0 };
  const local = e => { const r = el.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };

  el.addEventListener('pointerdown', e => {
    el.setPointerCapture(e.pointerId);
    if (!pts.size) { startedAt = performance.now(); travel = 0; maxPts = 0; }
    const dot = h('div', { class: 'dot' });
    el.append(dot);
    place(dot, ...local(e));
    pts.set(e.pointerId, { x: e.clientX, y: e.clientY, dot });
    maxPts = Math.max(maxPts, pts.size);
  });
  el.addEventListener('pointermove', e => {
    const p = pts.get(e.pointerId);
    if (!p) return;
    const dx = e.clientX - p.x, dy = e.clientY - p.y;
    p.x = e.clientX; p.y = e.clientY;
    place(p.dot, ...local(e));
    travel += Math.abs(dx) + Math.abs(dy);
    if (pts.size === 1) { acc.dx += dx; acc.dy += dy; } else { acc.sy += dy / pts.size; }
    if (!raf) raf = requestAnimationFrame(flush);
  });
  function flush() {
    raf = 0;
    if (acc.dx || acc.dy) send(`move ${fmt(acc.dx)} ${fmt(acc.dy)}`);
    if (acc.sy) send(`scroll ${fmt(acc.sy)}`);
    acc = { dx: 0, dy: 0, sy: 0 };
  }
  const lift = e => {
    const p = pts.get(e.pointerId);
    if (!p) return;
    p.dot.remove();
    pts.delete(e.pointerId);
    if (pts.size || e.type === 'pointercancel') return;
    if (travel < 12 && performance.now() - startedAt < 300) {
      const right = maxPts > 1;
      send(right ? 'right-click' : 'click');
      const r = h('div', { class: right ? 'ripple right' : 'ripple' });
      place(r, ...local(e));
      el.append(r);
      r.addEventListener('animationend', () => r.remove());
    }
  };
  el.addEventListener('pointerup', lift);
  el.addEventListener('pointercancel', lift);
  return el;
}

function scrollStrip() {
  const el = h('div', { class: 'strip' }, '⇕');
  let y = null;
  el.addEventListener('pointerdown', e => { e.stopPropagation(); el.setPointerCapture(e.pointerId); y = e.clientY; el.classList.add('on'); });
  el.addEventListener('pointermove', e => {
    if (y == null) return;
    const d = e.clientY - y;
    y = e.clientY;
    if (d) send(`scroll ${fmt(d)}`);
  });
  const up = () => { y = null; el.classList.remove('on'); };
  el.addEventListener('pointerup', up);
  el.addEventListener('pointercancel', up);
  return el;
}

function keyboardPanel() {
  const mods = new Set();
  const input = h('input', {
    class: 'kb-input', type: 'text', autocomplete: 'off', autocorrect: 'off', autocapitalize: 'off',
    spellcheck: 'false', enterkeyhint: 'send', placeholder: 'Tap here to type on the Mac',
  });
  input.addEventListener('input', e => {
    if (e.inputType === 'deleteContentBackward') send('key Backspace');
    else if (mods.size && e.data?.length === 1) send(`key ${combo(e.data)}`);
    else send(`type “${e.data ?? ''}”`);
  });
  input.addEventListener('keydown', e => { if (e.key === 'Enter') send('key Return'); });

  // Keep the iOS keyboard up when a bar key is tapped mid-typing.
  let typing = false;
  const keep = b => {
    b.addEventListener('pointerdown', () => { typing = document.activeElement === input; });
    b.addEventListener('mousedown', e => e.preventDefault());
    return b;
  };
  const after = () => { if (typing) input.focus(); };
  const combo = k => {
    const c = [...mods, k].join('+');
    mods.clear();
    el.querySelectorAll('.mod.on').forEach(b => b.classList.remove('on'));
    return c;
  };
  const mod = (sym, name) => {
    const b = keep(h('button', {
      class: 'key mod',
      onclick: () => {
        if (mods.has(name)) mods.delete(name); else mods.add(name);
        b.classList.toggle('on', mods.has(name));
        send(`hold ${[...mods].join('+') || 'nothing'}`);
        after();
      },
    }, sym));
    return b;
  };
  const key = (sym, name) => keep(h('button', { class: 'key', onclick: () => { send(`key ${combo(name)}`); after(); } }, sym));
  const chip = (label, name) => keep(h('button', { class: 'chip', onclick: () => { send(`shortcut ${name}`); after(); } }, label));

  const el = h('div', { class: 'panel kb' },
    input,
    h('div', { class: 'row' }, mod('⌘', 'cmd'), mod('⌥', 'opt'), mod('⌃', 'ctrl'), mod('⇧', 'shift'), key('esc', 'Esc'), key('⇥', 'Tab')),
    h('div', { class: 'row' }, key('←', 'Left'), key('↑', 'Up'), key('↓', 'Down'), key('→', 'Right'), key('⌫', 'Backspace'), key('⏎', 'Return')),
    h('div', { class: 'chips' },
      chip('⌘⇥ Switch app', 'cmd+Tab'), chip('⌘␣ Spotlight', 'cmd+Space'), chip('Mission Control', 'MissionControl'),
      chip('⌘W Close', 'cmd+W'), chip('⌘Q Quit', 'cmd+Q')));
  return el;
}

function slider(initial, onchange) {
  let v = initial;
  const fill = h('div', { class: 'fill' }), label = h('span');
  const el = h('div', { class: 'slider' }, fill, label);
  const show = () => { fill.style.width = `${v}%`; label.textContent = `Volume ${v}`; };
  const at = e => {
    const r = el.getBoundingClientRect();
    v = Math.round(Math.min(100, Math.max(0, ((e.clientX - r.left) / r.width) * 100)));
    show();
    onchange(v);
  };
  el.addEventListener('pointerdown', e => { el.setPointerCapture(e.pointerId); at(e); });
  el.addEventListener('pointermove', e => { if (el.hasPointerCapture(e.pointerId)) at(e); });
  show();
  return { el, set(n) { v = n; show(); } };
}

function mediaPanel() {
  let playing = false, vol = 40, muted = false;
  const play = h('button', {
    class: 'play', html: ICON.play,
    onclick: () => { playing = !playing; play.innerHTML = playing ? ICON.pause : ICON.play; send(playing ? 'media play' : 'media pause'); },
  });
  const s = slider(vol, v => { vol = v; send(`volume ${v}`); });
  const step = d => { vol = Math.min(100, Math.max(0, vol + d)); s.set(vol); send(`volume ${vol}`); };
  const mute = h('button', {
    html: ICON.speaker,
    onclick: () => { muted = !muted; mute.classList.toggle('on', muted); send(muted ? 'mute' : 'unmute'); },
  });
  return h('div', { class: 'panel media' },
    h('div', { class: 'np' },
      h('div', { class: 'np-art' }),
      h('div', {}, h('div', { class: 'np-title' }, 'Song Title'), h('div', { class: 'np-sub' }, 'Artist · now-playing is still undecided for v1'))),
    h('div', { class: 'transport' },
      h('button', { html: ICON.prev, onclick: () => send('media previous') }),
      play,
      h('button', { html: ICON.next, onclick: () => send('media next') })),
    h('div', { class: 'vol' },
      mute,
      h('button', { onclick: () => step(-6) }, '−'),
      s.el,
      h('button', { onclick: () => step(6) }, '+')));
}

function presentationPanel(extra) {
  let startedAt = 0, black = false;
  const clock = h('div', { class: 'clock' }, '00:00');
  const startClock = () => {
    if (startedAt) return;
    startedAt = Date.now();
    const tick = setInterval(() => {
      const s = Math.floor((Date.now() - startedAt) / 1000);
      clock.textContent = `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
    }, 1000);
  };
  const blackBtn = h('button', {
    class: 'black',
    onclick: () => { black = !black; blackBtn.classList.toggle('on', black); send(black ? 'screen black' : 'screen restore'); },
  }, 'Black');
  const laser = h('button', { class: 'laser' }, 'Hold for Laser');
  laser.addEventListener('pointerdown', e => { laser.setPointerCapture(e.pointerId); laser.classList.add('on'); send('laser show'); });
  const off = () => { if (laser.classList.contains('on')) { laser.classList.remove('on'); send('laser hide'); } };
  laser.addEventListener('pointerup', off);
  laser.addEventListener('pointercancel', off);
  laser.addEventListener('contextmenu', e => e.preventDefault());
  return h('div', { class: 'panel pres' },
    h('div', { class: 'pres-top' }, extra, clock, blackBtn),
    h('button', { class: 'next', onclick: () => { startClock(); send('slide next'); } }, 'Next ›'),
    h('div', { class: 'pres-bottom' },
      h('button', { class: 'prev', onclick: () => send('slide previous') }, '‹ Prev'),
      laser));
}

function panelFor(m) {
  return { keyboard: keyboardPanel, media: mediaPanel, presentation: presentationPanel }[m]();
}

// ---------- A: Tab bar — iOS-standard bottom tabs, each Mode owns the whole screen ----------

function VariantA(root) {
  const views = Object.fromEntries(MODES.map(m => [m, h('section', { class: 'a-view' },
    m === 'trackpad'
      ? h('div', { class: 'a-pad' },
          h('div', { class: 'a-pad-main' }, trackpad(), scrollStrip()),
          h('div', { class: 'a-clicks' },
            h('button', { onclick: () => send('click') }, 'Left click'),
            h('button', { onclick: () => send('right-click') }, 'Right click')))
      : panelFor(m))]));
  const tabs = MODES.map(m => h('button', { class: 'tab', onclick: () => go(m) },
    h('span', { class: 'ico', html: ICON[m] }), SHORT[m]));
  root.append(h('div', { class: 'a' }, h('main', { class: 'a-main' }, Object.values(views)), h('nav', { class: 'tabbar' }, tabs)));

  function go(m) {
    document.activeElement?.blur();
    MODES.forEach((k, i) => { views[k].classList.toggle('on', k === m); tabs[i].classList.toggle('on', k === m); });
    setMode(m);
  }
  go(state.mode);
}

// ---------- B: Swipe pager — no chrome, full-bleed Modes, swipe the top bar or in from a screen edge ----------

function VariantB(root) {
  let i = MODES.indexOf(state.mode);
  const pages = MODES.map(m => h('section', { class: 'b-page' },
    m === 'trackpad'
      ? trackpad('One finger moves · tap clicks · two fingers scroll · swipe the top bar or in from a screen edge to change Mode')
      : panelFor(m)));
  const track = h('div', { class: 'b-track drag' }, pages);
  const title = h('div', { class: 'b-title' });
  const dots = h('div', { class: 'b-dots' }, MODES.map((m, k) => h('i', { onclick: () => go(k) })));
  const strip = h('header', { class: 'b-strip' },
    h('button', { class: 'b-arrow', onclick: () => go(i - 1) }, '‹'),
    h('div', { class: 'b-center' }, title, dots),
    h('button', { class: 'b-arrow', onclick: () => go(i + 1) }, '›'));
  const view = h('div', { class: 'b-viewport' }, track, h('div', { class: 'b-edge left' }), h('div', { class: 'b-edge right' }));
  root.append(h('div', { class: 'b' }, strip, view));

  function go(n) {
    i = Math.max(0, Math.min(MODES.length - 1, n));
    track.style.transform = `translateX(${-i * 25}%)`;
    title.textContent = NAME[MODES[i]];
    [...dots.children].forEach((d, k) => d.classList.toggle('on', k === i));
    document.activeElement?.blur();
    setMode(MODES[i]);
  }

  let drag = null;
  const begin = e => { drag = { id: e.pointerId, x: e.clientX, dx: 0 }; track.classList.add('drag'); };
  strip.addEventListener('pointerdown', e => {
    if (e.target.closest('button, i')) return;
    strip.setPointerCapture(e.pointerId);
    begin(e);
  });
  // Capture phase so an edge swipe never reaches the trackpad underneath.
  view.addEventListener('pointerdown', e => {
    const r = view.getBoundingClientRect();
    if (e.clientX - r.left > 14 && r.right - e.clientX > 14) return;
    e.stopPropagation();
    view.setPointerCapture(e.pointerId);
    begin(e);
  }, true);
  const moveDrag = e => {
    if (!drag || e.pointerId !== drag.id) return;
    drag.dx = e.clientX - drag.x;
    track.style.transform = `translateX(calc(${-i * 25}% + ${drag.dx}px))`;
  };
  const endDrag = e => {
    if (!drag || e.pointerId !== drag.id) return;
    const dx = drag.dx;
    drag = null;
    track.classList.remove('drag');
    go(Math.abs(dx) > 60 ? i - Math.sign(dx) : i);
  };
  for (const t of [strip, view]) {
    t.addEventListener('pointermove', moveDrag);
    t.addEventListener('pointerup', endDrag);
    t.addEventListener('pointercancel', endDrag);
  }

  go(i);
  requestAnimationFrame(() => track.classList.remove('drag'));
}

// ---------- C: Thumb hub — trackpad is home; a thumb button fans out Modes; Keys/Media are drawers ----------

function VariantC(root) {
  const panels = { keyboard: keyboardPanel(), media: mediaPanel() };
  const drawer = h('div', { class: 'c-drawer' });
  const fabIcon = h('span', { class: 'ico' });
  const fab = h('button', { class: 'c-fab', 'aria-label': 'Change Mode' }, fabIcon);
  const items = MODES.map((m, k) => {
    const a = ((90 + k * 30) * Math.PI) / 180;
    return h('button', { class: 'c-item', 'data-mode': m, style: `--x:${Math.cos(a) * 118}px;--y:${-Math.sin(a) * 118}px` },
      h('span', { class: 'ico', html: ICON[m] }), h('small', {}, SHORT[m]));
  });
  const top = h('div', { class: 'c-top' },
    trackpad('Trackpad is home · tap the blue button for Modes, or press and slide onto one'),
    scrollStrip(),
    h('div', { class: 'c-scrim', onclick: () => fanOpen(false) }),
    h('div', { class: 'c-fan' }, items),
    fab);
  const takeover = h('div', { class: 'c-takeover' }, presentationPanel(h('button', { class: 'exit', onclick: () => go('trackpad') }, '✕')));
  const el = h('div', { class: 'c' }, top, drawer, takeover);
  root.append(el);

  function fanOpen(on) { top.classList.toggle('fan-open', on); }
  function go(m) {
    fanOpen(false);
    document.activeElement?.blur();
    drawer.replaceChildren();
    if (panels[m]) drawer.append(h('button', { class: 'grabber', 'aria-label': 'Close', onclick: () => go('trackpad') }), panels[m]);
    drawer.classList.toggle('on', !!panels[m]);
    el.classList.toggle('drawer-open', !!panels[m]);
    takeover.classList.toggle('on', m === 'presentation');
    fabIcon.innerHTML = ICON[m];
    items.forEach(b => b.classList.toggle('on', b.dataset.mode === m));
    setMode(m);
  }

  // Tap opens the fan; press-slide-release picks a Mode in one motion.
  let wasOpen = false;
  const hitAt = e => document.elementFromPoint(e.clientX, e.clientY)?.closest('.c-item');
  fab.addEventListener('pointerdown', e => {
    fab.setPointerCapture(e.pointerId);
    wasOpen = top.classList.contains('fan-open');
    fanOpen(true);
  });
  fab.addEventListener('pointermove', e => { const hit = hitAt(e); items.forEach(b => b.classList.toggle('hover', b === hit)); });
  fab.addEventListener('pointerup', e => {
    const hit = hitAt(e);
    items.forEach(b => b.classList.remove('hover'));
    if (hit) go(hit.dataset.mode);
    else if (wasOpen) fanOpen(false);
  });
  fab.addEventListener('pointercancel', () => items.forEach(b => b.classList.remove('hover')));
  items.forEach(b => b.addEventListener('click', () => go(b.dataset.mode)));

  go(state.mode);
}

// ---------- D: Split console — trackpad always visible, Mode panel beside/below it; rotate to landscape ----------

function VariantD(root) {
  const panels = { keyboard: keyboardPanel(), media: mediaPanel(), presentation: presentationPanel() };
  const panel = h('div', { class: 'd-panel' });
  const seg = h('div', { class: 'seg' }, MODES.map(m => h('button', { 'data-mode': m, onclick: () => go(m) }, SHORT[m])));
  const el = h('div', { class: 'd' },
    h('div', { class: 'd-padarea' }, trackpad('Trackpad stays live in every Mode · try landscape'), scrollStrip()),
    seg,
    panel);
  root.append(el);

  function go(m) {
    document.activeElement?.blur();
    panel.replaceChildren(...(panels[m] ? [panels[m]] : []));
    el.classList.toggle('full', !panels[m]);
    [...seg.children].forEach(b => b.classList.toggle('on', b.dataset.mode === m));
    setMode(m);
  }
  go(state.mode);
}

// ---------- prototype switcher + viewport plumbing ----------

const pillLabel = h('div', { class: 'pill-label' });
const pillTick = h('div', { class: 'pill-tick' });
const pill = h('div', { class: 'pill' },
  h('button', { 'aria-label': 'Previous variant', onclick: () => cycle(-1) }, '‹'),
  h('div', { class: 'pill-mid', onclick: () => pill.classList.toggle('min') }, pillLabel, pillTick),
  h('button', { 'aria-label': 'Next variant', onclick: () => cycle(1) }, '›'));

function renderPill() {
  pillLabel.innerHTML = `<b>${state.variant}</b><span> · ${VARIANTS[state.variant][0]} · ${NAME[state.mode]}</span>`;
  pillTick.textContent = `→ ${state.last}`;
}
function cycle(step) {
  const keys = Object.keys(VARIANTS);
  state.variant = keys[(keys.indexOf(state.variant) + step + keys.length) % keys.length];
  render();
}
function render() {
  document.activeElement?.blur();
  app.replaceChildren();
  VARIANTS[state.variant][1](app);
  syncUrl();
  renderPill();
}
addEventListener('keydown', e => {
  if (e.target.matches('input, textarea, [contenteditable]')) return;
  if (e.key === 'ArrowLeft') cycle(-1);
  if (e.key === 'ArrowRight') cycle(1);
});

const app = document.getElementById('app');
document.body.append(pill);

// Track the visual viewport so bars sit right above the iOS keyboard instead of under it.
const vv = window.visualViewport;
if (vv) {
  const fit = () => {
    document.documentElement.style.setProperty('--vvh', `${vv.height}px`);
    app.style.transform = `translateY(${vv.offsetTop}px)`;
  };
  vv.addEventListener('resize', fit);
  vv.addEventListener('scroll', fit);
  fit();
}
document.addEventListener('gesturestart', e => e.preventDefault());
document.addEventListener('focusout', () => setTimeout(() => scrollTo(0, 0), 50));

render();
