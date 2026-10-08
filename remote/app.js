import { createKeyboard } from './keyboard.js';
import { LASER, airDelta, dragDelta, rotationVector } from './laser.js';
import { createSender } from './sender.js';
import { DEFAULTS, createScrollStrip, createTrackpad } from './trackpad.js';
import { createVolumeSlider } from './volume-slider.js';

// ---------- Modes ----------

const MODES = ['trackpad', 'keyboard', 'media', 'presentation'];
/** Mode panels by Mode (Trackpad has none); built further down. */
const PANELS = {};

const app = document.getElementById('app');
const panel = document.getElementById('panel');
const modeButtons = document.querySelectorAll('#modes button');

/** The Home Screen app always relaunches at start_url, so the last Mode comes from storage. */
function storedMode() {
  try {
    const mode = localStorage.getItem('mode');
    return MODES.includes(mode) ? mode : 'trackpad';
  } catch {
    return 'trackpad';
  }
}

function showMode(mode) {
  // Switching Mode dismisses the iOS keyboard, and the Mac's text cursor may move meanwhile.
  if (mode !== app.dataset.mode) {
    field.blur();
    keyboard.reset();
    renderKeys();
  }
  if (mode !== 'presentation' && shown) endLaser();
  app.dataset.mode = mode;
  app.classList.toggle('full', mode === 'trackpad');
  app.classList.toggle('presenting', mode === 'presentation');
  if (PANELS[mode]) panel.replaceChildren(PANELS[mode]);
  else panel.replaceChildren();
  panel.classList.toggle('filled', Boolean(PANELS[mode]));
  keepAwake(mode === 'presentation');
  for (const b of modeButtons) b.classList.toggle('on', b.dataset.mode === mode);
  try { localStorage.setItem('mode', mode); } catch {}
}

for (const b of modeButtons) {
  b.addEventListener('click', () => {
    showMode(b.dataset.mode);
    // Keys raises the iOS keyboard straight away; focus has to happen inside the tap to do that.
    if (b.dataset.mode === 'keyboard') field.focus();
  });
}

// ---------- Connection ----------

const conn = document.getElementById('conn');
let sender = createSender({ readyState: 3, bufferedAmount: 0, send() {} });
/** The Host closes the socket with this when the Remote isn't paired, or was just revoked. */
const UNPAIRED = 4401;

function connect() {
  const socket = new WebSocket(`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws`);
  sender = createSender(socket);
  socket.addEventListener('open', () => conn.classList.add('on'));
  socket.addEventListener('message', (e) => {
    let message;
    try { message = JSON.parse(e.data); } catch { return; }
    if (message.t === 'vol') {
      volumeSlider.host(message, performance.now());
      renderVolume();
    }
  });
  socket.addEventListener('close', (e) => {
    conn.classList.remove('on');
    if (e.code === UNPAIRED) showPairing(e.reason);
    else if (pairing.hidden) setTimeout(connect, 1000);
  });
}
connect();

// ---------- Pairing ----------

const pairing = document.getElementById('pairing');
const pairForm = document.getElementById('pair-form');
const pairCode = document.getElementById('pair-code');
const pairError = document.getElementById('pair-error');
const pairButton = document.getElementById('pair-button');

const PAIR_ERRORS = {
  wrongCode: 'That’s not the code. Try again.',
  tooManyTries: 'Too many wrong tries. Ask the Mac for a new code.',
  noCode: 'No code is waiting. Choose Pair a Remote… on the Mac.',
  notOnTailnet: 'The Remote isn’t reaching the Mac through Tailscale.',
  otherOrigin: 'Open the Remote from its own address.',
  otherLogin: 'This Remote paired under another Tailscale account. Pair it again.',
};

/** @param {string} [why] the Host's reason; only the ones pairing again won't fix are worth showing up front. */
function showPairing(why) {
  pairError.textContent = ['notOnTailnet', 'otherOrigin', 'otherLogin'].includes(why) ? PAIR_ERRORS[why] : '';
  // A Home Screen app has its own cookies, so pairing in a Safari tab doesn't carry over.
  const standalone = navigator.standalone === true || matchMedia('(display-mode: standalone)').matches;
  document.getElementById('pair-hint').hidden = standalone;
  pairing.hidden = false;
}

async function pair() {
  const code = pairCode.value.replace(/\D/g, '');
  if (code.length !== 6) return;
  pairButton.disabled = true;
  pairError.textContent = '';
  try {
    const response = await fetch('/pair', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code }),
    });
    const body = await response.json().catch(() => ({}));
    if (response.ok) {
      pairing.hidden = true;
      pairCode.value = '';
      connect();
    } else {
      pairError.textContent = PAIR_ERRORS[body.error] ?? 'The Mac refused the code.';
      pairCode.select();
    }
  } catch {
    pairError.textContent = 'Can’t reach the Mac.';
  } finally {
    pairButton.disabled = false;
  }
}

pairForm.addEventListener('submit', (e) => { e.preventDefault(); pair(); });
// Pair as soon as the sixth digit is in.
pairCode.addEventListener('input', () => { if (pairCode.value.replace(/\D/g, '').length === 6) pair(); });

document.getElementById('unpair').addEventListener('click', async () => {
  if (!confirm('Unpair this Remote? To use it again, you’ll need a new code from the Mac.')) return;
  await fetch('/unpair', { method: 'POST' }).catch(() => {});
  sheet.close();
  showPairing();
});

// Send whatever backpressure held back, once per frame.
(function drainEachFrame() {
  sender.drain();
  requestAnimationFrame(drainEachFrame);
})();

/** Motion and scroll are coalesced; everything else goes out as is. */
function dispatch(commands) {
  for (const c of commands) {
    if (c.t === 'm') sender.move(c.dx, c.dy);
    else if (c.t === 's') sender.scroll(c.dx, c.dy);
    else sender.send(c);
  }
}

// ---------- Trackpad settings (per device) ----------

const SETTINGS = [
  // key, label, min, max, step
  ['sens', 'Speed', 0.5, 4, 0.1],
  ['accel', 'Acceleration', 0, 4, 0.1],
  ['scroll', 'Scroll speed', 0.3, 4, 0.1],
];

function loadParams() {
  try {
    return { ...DEFAULTS, ...JSON.parse(localStorage.getItem('trackpad') ?? '{}') };
  } catch {
    return { ...DEFAULTS };
  }
}
let params = loadParams();

function saveParams() {
  try { localStorage.setItem('trackpad', JSON.stringify(params)); } catch {}
  rebuildGestures();
}

const sheet = document.getElementById('sheet');
const settings = document.getElementById('settings');

function renderSettings() {
  settings.replaceChildren();
  const heading = (text) => {
    const h = document.createElement('h3');
    h.textContent = text;
    settings.append(h);
  };
  heading('Trackpad');
  for (const [key, label, min, max, step] of SETTINGS) {
    const row = document.createElement('div');
    row.className = 'setting';
    row.innerHTML = `<label for="set-${key}">${label}</label><input id="set-${key}" type="range" min="${min}" max="${max}" step="${step}"><output></output>`;
    const input = row.querySelector('input'), output = row.querySelector('output');
    input.value = params[key];
    output.textContent = params[key];
    input.addEventListener('input', () => {
      params[key] = Number(input.value);
      output.textContent = input.value;
      saveParams();
    });
    settings.append(row);
  }
  const row = document.createElement('div');
  row.className = 'setting';
  row.innerHTML = '<label for="set-momentum">Momentum</label><input id="set-momentum" type="checkbox">';
  const box = row.querySelector('input');
  box.checked = params.momentum;
  box.addEventListener('change', () => { params.momentum = box.checked; saveParams(); });
  settings.append(row);

  heading('Laser');
  const steering = document.createElement('div');
  steering.className = 'setting';
  steering.innerHTML = `<label>Steer with</label><div class="seg">
    <button type="button" data-steer="motion">Motion</button><button type="button" data-steer="drag">Drag</button></div>`;
  for (const b of steering.querySelectorAll('[data-steer]')) {
    b.classList.toggle('on', b.dataset.steer === steer);
    b.addEventListener('click', () => { setSteer(b.dataset.steer); renderSettings(); });
  }
  settings.append(steering);
}

function openSettings() {
  renderSettings();
  sheet.showModal();
}
document.getElementById('gear').addEventListener('click', openSettings);
document.getElementById('reset').addEventListener('click', () => {
  params = { ...DEFAULTS };
  setSteer('motion');
  saveParams();
  renderSettings();
});

// ---------- Trackpad and scroll strip ----------

const pad = document.getElementById('pad');
const strip = document.getElementById('strip');
let trackpad, scrollStrip;

function rebuildGestures() {
  trackpad = createTrackpad(params);
  scrollStrip = createScrollStrip(params);
}
rebuildGestures();

const touchesOf = (list) => Array.from(list, (t) => ({ id: t.identifier, x: t.clientX, y: t.clientY }));

/** Feeds a surface's touches to its gesture recognizer; motion is sent straight from touchmove. */
function listen(el, recognizer, onCommands = () => {}) {
  const handle = (phase) => (e) => {
    if (e.target.closest('button')) return; // the gear is a normal button
    e.preventDefault();
    const commands = recognizer()[phase](touchesOf(e.targetTouches), e.timeStamp);
    onCommands(commands, e.targetTouches.length);
    dispatch(commands);
  };
  el.addEventListener('touchstart', handle('start'), { passive: false });
  el.addEventListener('touchmove', handle('move'), { passive: false });
  el.addEventListener('touchend', handle('end'), { passive: false });
  el.addEventListener('touchcancel', handle('end'), { passive: false });
}

listen(pad, () => trackpad, (commands) => {
  for (const c of commands) {
    // A click may move the Mac's text cursor: don't let a later correction erase across it.
    if (c.t === 'c' || c.t === 'd') resetTyping();
    if (c.t === 'd') pad.classList.add('drag');
    if (c.t === 'u') pad.classList.remove('drag');
  }
});
listen(strip, () => scrollStrip, (_, down) => strip.classList.toggle('on', down > 0));

// ---------- Media Mode ----------

const volumeSlider = createVolumeSlider();
const media = document.createElement('div');
media.className = 'media';
media.innerHTML = `
  <div class="transport">
    <button data-key="prev" aria-label="Previous">⏮</button>
    <button data-key="play" class="play" aria-label="Play or pause">⏯</button>
    <button data-key="next" aria-label="Next">⏭</button>
  </div>
  <div class="volume">
    <button data-key="voldown" aria-label="Volume down">−</button>
    <div class="slider" id="slider" role="slider" aria-label="Volume" aria-valuemin="0" aria-valuemax="100">
      <div class="fill"></div><span></span>
    </div>
    <button data-key="volup" aria-label="Volume up">+</button>
    <button data-key="mute" class="mute" aria-label="Mute">🔇</button>
  </div>`;
PANELS.media = media;

for (const b of media.querySelectorAll('[data-key]')) {
  b.addEventListener('click', () => sender.send({ t: 'k', k: b.dataset.key }));
}

const slider = media.querySelector('#slider');
const fill = slider.querySelector('.fill');
const readout = slider.querySelector('span');

function renderVolume() {
  const { level, muted, settable } = volumeSlider.state;
  fill.style.width = `${level * 100}%`;
  readout.textContent = settable ? `${Math.round(level * 100)}%` : 'Use − and +';
  slider.classList.toggle('muted', muted);
  slider.classList.toggle('fixed', !settable);
  slider.setAttribute('aria-valuenow', String(Math.round(level * 100)));
  media.querySelector('.mute').classList.toggle('on', muted);
}

function slide(e) {
  e.preventDefault();
  if (!volumeSlider.state.settable) return;
  const box = slider.getBoundingClientRect();
  const level = volumeSlider.touch((e.touches[0].clientX - box.left) / box.width, e.timeStamp);
  sender.volume(level);
  renderVolume();
}
slider.addEventListener('touchstart', slide, { passive: false });
slider.addEventListener('touchmove', slide, { passive: false });
for (const type of ['touchend', 'touchcancel']) {
  slider.addEventListener(type, (e) => {
    e.preventDefault();
    if (e.touches.length === 0) volumeSlider.release(performance.now());
  }, { passive: false });
}
renderVolume();

// ---------- Keyboard Mode ----------

const keyboard = createKeyboard();
const keys = document.createElement('div');
keys.className = 'keys';
keys.innerHTML = `
  <label class="typed">
    <span class="text"></span>
    <textarea rows="1" autocapitalize="off" autocomplete="off" autocorrect="off" spellcheck="false"
      enterkeyhint="enter" aria-label="Type on the Mac"></textarea>
  </label>
  <div class="keyrow">
    <button data-key="esc">esc</button>
    <button data-key="tab">tab</button>
    <button data-mod="ctrl" aria-label="Control">⌃</button>
    <button data-mod="opt" aria-label="Option">⌥</button>
    <button data-mod="cmd" aria-label="Command">⌘</button>
    <button data-mod="shift" aria-label="Shift">⇧</button>
  </div>
  <div class="keyrow">
    <button data-key="left" data-repeat aria-label="Left">←</button>
    <button data-key="up" data-repeat aria-label="Up">↑</button>
    <button data-key="down" data-repeat aria-label="Down">↓</button>
    <button data-key="right" data-repeat aria-label="Right">→</button>
    <button data-key="fwddel" data-repeat aria-label="Forward delete">⌦</button>
    <button data-toggle class="toggle" aria-label="Show or hide the keyboard">⌨︎</button>
  </div>
  <div class="keyrow palette">
    <button data-palette="appSwitcher">App switcher</button>
    <button data-palette="spotlight">Spotlight</button>
    <button data-palette="missionControl">Mission Control</button>
  </div>`;
PANELS.keyboard = keys;

const field = keys.querySelector('textarea');
const typedText = keys.querySelector('.typed .text');
const typing = () => document.activeElement === field;

function renderKeys() {
  typedText.textContent = keyboard.typed;
  for (const b of keys.querySelectorAll('[data-mod]')) {
    const state = keyboard.mods.state(b.dataset.mod);
    b.classList.toggle('once', state === 'once');
    b.classList.toggle('locked', state === 'locked');
  }
}

/** Sets the field to what the keyboard model expects, with the caret at the end. */
function syncField() {
  if (field.value !== keyboard.field) field.value = keyboard.field;
  field.setSelectionRange(field.value.length, field.value.length);
}

function resetTyping() {
  keyboard.reset();
  syncField();
  renderKeys();
}

field.addEventListener('input', () => {
  dispatch(keyboard.input(field.value));
  syncField();
  renderKeys();
});

// While the iOS keyboard is up, fit the console into what's left of the screen above it.
function fitViewport() {
  const vv = window.visualViewport;
  if (vv && typing()) {
    app.style.top = `${vv.offsetTop}px`;
    app.style.height = `${vv.height}px`;
  } else {
    app.style.removeProperty('top');
    app.style.removeProperty('height');
  }
}
window.visualViewport?.addEventListener('resize', fitViewport);
window.visualViewport?.addEventListener('scroll', fitViewport);

field.addEventListener('focus', () => {
  app.classList.add('typing');
  syncField();
  fitViewport();
});
field.addEventListener('blur', () => {
  app.classList.remove('typing');
  fitViewport();
});

/** Auto-repeat for held arrows and ⌦: 400 ms, then about 30 a second. */
let repeat = null;
function startRepeat(commands) {
  stopRepeat();
  repeat = setTimeout(function again() {
    dispatch(commands);
    repeat = setTimeout(again, 33);
  }, 400);
}
function stopRepeat() {
  clearTimeout(repeat);
  repeat = null;
}

// Keys act on touch-down, and cancelling it keeps the focus (and the iOS keyboard) where it is.
keys.addEventListener('touchstart', (e) => {
  const b = e.target.closest('button');
  if (!b) return;
  e.preventDefault();
  b.classList.add('down');
  if (b.dataset.mod) {
    keyboard.mods.tap(b.dataset.mod, e.timeStamp);
  } else if (b.dataset.key) {
    const commands = keyboard.key(b.dataset.key);
    dispatch(commands);
    if ('repeat' in b.dataset) startRepeat(commands);
    syncField();
  }
  renderKeys();
}, { passive: false });

function lift(e) {
  const b = e.target.closest('button');
  if (!b) return;
  e.preventDefault();
  b.classList.remove('down');
  stopRepeat();
  if (e.type === 'touchcancel') return;
  // These change focus, which iOS allows only on touch-up.
  if ('toggle' in b.dataset) {
    if (typing()) field.blur();
    else field.focus();
  } else if (b.dataset.palette) {
    dispatch(keyboard[b.dataset.palette]());
    syncField();
    renderKeys();
    if (b.dataset.palette === 'spotlight') field.focus();
  }
}
keys.addEventListener('touchend', lift, { passive: false });
keys.addEventListener('touchcancel', lift, { passive: false });

syncField();
renderKeys();

// ---------- Presentation Mode ----------

const present = document.createElement('div');
present.className = 'present';
present.innerHTML = `
  <button class="prev" data-slide="pgup" aria-label="Previous slide">‹ Prev</button>
  <button class="black" aria-label="Black screen (hold)">Black<small>hold</small></button>
  <button class="next" data-slide="pgdn" aria-label="Next slide">Next ›</button>
  <div class="aim">
    <div class="aim-bar">
      <div class="aim-switch" role="tablist">
        <button data-aim="laser" role="tab">Laser</button>
        <button data-aim="pointer" role="tab">Pointer</button>
      </div>
      <button class="aim-gear" aria-label="Settings">⚙︎</button>
    </div>
    <div class="zone" role="button" aria-label="Laser (hold)"><span>Hold for Laser</span></div>
    <div class="pointer-pad" aria-label="Trackpad for the pointer"></div>
  </div>`;
PANELS.presentation = present;

const zone = present.querySelector('.zone');
const pointerPad = present.querySelector('.pointer-pad');
present.querySelector('.aim-gear').addEventListener('click', openSettings);

// The aim area is either the Laser zone or a trackpad for the real pointer, say to click a link or
// start a video; the choice is kept per device.
function setAim(aim) {
  present.dataset.aim = aim;
  for (const b of present.querySelectorAll('[data-aim]')) b.classList.toggle('on', b.dataset.aim === aim);
  try { localStorage.setItem('aim', aim); } catch {}
}
for (const b of present.querySelectorAll('[data-aim]')) b.addEventListener('click', () => setAim(b.dataset.aim));
setAim((() => { try { return localStorage.getItem('aim') === 'pointer' ? 'pointer' : 'laser'; } catch { return 'laser'; } })());

listen(pointerPad, () => trackpad, (commands) => {
  for (const c of commands) {
    if (c.t === 'd') pointerPad.classList.add('drag');
    if (c.t === 'u') pointerPad.classList.remove('drag');
  }
});
const black = present.querySelector('.black');

// Next and Prev act on touch-down, like a clicker.
for (const b of present.querySelectorAll('[data-slide]')) {
  b.addEventListener('touchstart', (e) => {
    e.preventDefault();
    b.classList.add('down');
    sender.send({ t: 'kp', k: b.dataset.slide });
  }, { passive: false });
  for (const type of ['touchend', 'touchcancel']) b.addEventListener(type, () => b.classList.remove('down'));
}

// Black needs a long press, so it can't be hit by accident.
const BLACK_MS = 600;
let blackTimer = null;
black.addEventListener('touchstart', (e) => {
  e.preventDefault();
  black.classList.add('down');
  blackTimer = setTimeout(() => {
    sender.send({ t: 'kp', c: 'b' });
    black.classList.add('fired');
  }, BLACK_MS);
}, { passive: false });
for (const type of ['touchend', 'touchcancel']) {
  black.addEventListener(type, () => {
    clearTimeout(blackTimer);
    black.classList.remove('down', 'fired');
  });
}

/** How the Laser is steered, per device: turning the phone (`motion`) or the thumb (`drag`). */
let steer = (() => { try { return localStorage.getItem('laserSteer') === 'drag' ? 'drag' : 'motion'; } catch { return 'motion'; } })();
function setSteer(value) {
  steer = value;
  try { localStorage.setItem('laserSteer', value); } catch {}
  renderZone();
  if (steer === 'motion') askMotion(); // from the tap that chose it
}

/**
 * Motion access: 'unknown' until asked, then 'granted' or 'denied'. iOS keeps the answer only until the app
 * closes, so it asks again on every launch: ask when the Laser is first used, not on entering Presentation
 * Mode, and steer by drag until it's granted.
 */
let motion = typeof DeviceMotionEvent?.requestPermission === 'function' ? 'unknown' : 'granted';
async function askMotion() {
  if (motion !== 'unknown' || steer !== 'motion') return;
  try {
    motion = (await DeviceMotionEvent.requestPermission()) === 'granted' ? 'granted' : 'denied';
  } catch {
    // Not inside a tap: ask again on the next one.
  }
  renderZone();
}

const dragging = () => steer === 'drag' || motion !== 'granted';
function renderZone() {
  zone.querySelector('span').textContent = dragging() ? 'Drag for Laser' : 'Hold for Laser';
}
renderZone();

let held = false; // a thumb is on the zone
let shown = false; // the Host is showing the dot
let linger = null; // timer that hides the dot after a drag
let lastMotion = null; // time of the last motion sample while held, ms
let lastTouch = null; // { x, y, t } of the thumb while dragging

zone.addEventListener('touchstart', (e) => {
  e.preventDefault();
  if (held) return;
  held = true;
  lastMotion = null;
  lastTouch = { x: e.touches[0].clientX, y: e.touches[0].clientY, t: e.timeStamp };
  zone.classList.add('on');
  // A new swipe while the dot lingers carries on from where it is.
  clearTimeout(linger);
  linger = null;
  if (!shown) {
    shown = true;
    sender.send({ t: 'ls' });
  }
}, { passive: false });

zone.addEventListener('touchmove', (e) => {
  e.preventDefault();
  if (!held || !dragging()) return;
  const t = e.targetTouches[0];
  const { dx, dy } = dragDelta(t.clientX - lastTouch.x, t.clientY - lastTouch.y, e.timeStamp - lastTouch.t, params);
  sender.laser(dx, dy);
  lastTouch = { x: t.clientX, y: t.clientY, t: e.timeStamp };
}, { passive: false });

for (const type of ['touchend', 'touchcancel']) {
  zone.addEventListener(type, (e) => {
    e.preventDefault();
    if (e.targetTouches.length > 0 || !held) return;
    held = false;
    if (dragging() && type === 'touchend') linger = setTimeout(endLaser, LASER.linger);
    else endLaser();
    // iOS only asks from a tap, and a release is one.
    if (type === 'touchend') askMotion();
  }, { passive: false });
}

function endLaser() {
  held = false;
  clearTimeout(linger);
  linger = null;
  zone.classList.remove('on');
  if (!shown) return;
  shown = false;
  sender.send({ t: 'le' });
}

window.addEventListener('devicemotion', (e) => {
  if (!held || dragging() || !e.rotationRate) return;
  const dt = lastMotion === null ? 0 : Math.min((e.timeStamp - lastMotion) / 1000, 0.1);
  lastMotion = e.timeStamp;
  const angle = screen.orientation?.angle ?? window.orientation ?? 0;
  const { dx, dy } = airDelta(rotationVector(e.rotationRate), e.accelerationIncludingGravity ?? {}, angle, dt);
  if (dx || dy) sender.laser(dx, dy);
});

// Keep the screen on while presenting. iOS drops the lock when the app goes to the background.
let wakeLock = null;
async function keepAwake(on) {
  if (!on) {
    wakeLock?.release().catch(() => {});
    wakeLock = null;
    return;
  }
  if (wakeLock && !wakeLock.released) return;
  try { wakeLock = await navigator.wakeLock?.request('screen'); } catch {}
}
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') keepAwake(app.dataset.mode === 'presentation');
});

showMode(storedMode());
