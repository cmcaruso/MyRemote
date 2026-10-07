import { createMotionSender } from './motion-sender.js';

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
let motion = createMotionSender({ readyState: 3, bufferedAmount: 0, send() {} });

function connect() {
  const socket = new WebSocket(`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws`);
  motion = createMotionSender(socket);
  socket.addEventListener('open', () => conn.classList.add('on'));
  socket.addEventListener('close', () => {
    conn.classList.remove('on');
    setTimeout(connect, 1000);
  });
}
connect();

// Send whatever backpressure held back, once per frame.
(function drainEachFrame() {
  motion.drain();
  requestAnimationFrame(drainEachFrame);
})();

// ---------- Trackpad: one-finger move ----------

/** Fixed gain until Trackpad Mode brings the acceleration curve. */
const GAIN = 1.6;
const pad = document.getElementById('pad');
let last = null;

pad.addEventListener('touchstart', (e) => {
  e.preventDefault();
  const t = e.touches[0];
  last = e.touches.length === 1 ? { id: t.identifier, x: t.clientX, y: t.clientY } : null;
}, { passive: false });

// Motion goes out straight from touchmove: waiting for rAF adds latency.
pad.addEventListener('touchmove', (e) => {
  e.preventDefault();
  if (!last || e.touches.length !== 1) return;
  const t = e.touches[0];
  if (t.identifier !== last.id) return;
  motion.add((t.clientX - last.x) * GAIN, (t.clientY - last.y) * GAIN);
  last = { id: t.identifier, x: t.clientX, y: t.clientY };
}, { passive: false });

pad.addEventListener('touchend', () => { last = null; });
pad.addEventListener('touchcancel', () => { last = null; });
