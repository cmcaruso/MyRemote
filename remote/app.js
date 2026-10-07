import { createSender } from './sender.js';
import { DEFAULTS, createScrollStrip, createTrackpad } from './trackpad.js';

// ---------- Modes ----------

const MODES = ['trackpad', 'keyboard', 'media', 'presentation'];
const PLACEHOLDER = {
  keyboard: 'Keyboard Mode is coming.',
  media: 'Media Mode is coming.',
  presentation: 'Presentation Mode is coming.',
};

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
  panel.textContent = PLACEHOLDER[mode] ?? '';
  for (const b of modeButtons) b.classList.toggle('on', b.dataset.mode === mode);
  try { localStorage.setItem('mode', mode); } catch {}
}

for (const b of modeButtons) b.addEventListener('click', () => showMode(b.dataset.mode));
showMode(storedMode());

// ---------- Connection ----------

const conn = document.getElementById('conn');
let sender = createSender({ readyState: 3, bufferedAmount: 0, send() {} });

function connect() {
  const socket = new WebSocket(`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws`);
  sender = createSender(socket);
  socket.addEventListener('open', () => conn.classList.add('on'));
  socket.addEventListener('close', () => {
    conn.classList.remove('on');
    setTimeout(connect, 1000);
  });
}
connect();

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
