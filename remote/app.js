import { createSender } from './sender.js';
import { DEFAULTS, createScrollStrip, createTrackpad } from './trackpad.js';
import { createVolumeSlider } from './volume-slider.js';

// ---------- Modes ----------

const MODES = ['trackpad', 'keyboard', 'media', 'presentation'];
const PLACEHOLDER = {
  keyboard: 'Keyboard Mode is coming.',
  presentation: 'Presentation Mode is coming.',
};
/** Mode panels that exist so far, by Mode; built further down. */
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
  app.classList.toggle('full', mode === 'trackpad');
  if (PANELS[mode]) panel.replaceChildren(PANELS[mode]);
  else panel.textContent = PLACEHOLDER[mode] ?? '';
  panel.classList.toggle('filled', Boolean(PANELS[mode]));
  for (const b of modeButtons) b.classList.toggle('on', b.dataset.mode === mode);
  try { localStorage.setItem('mode', mode); } catch {}
}

for (const b of modeButtons) b.addEventListener('click', () => showMode(b.dataset.mode));

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
}

document.getElementById('gear').addEventListener('click', () => { renderSettings(); sheet.showModal(); });
document.getElementById('reset').addEventListener('click', () => {
  params = { ...DEFAULTS };
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

showMode(storedMode());
