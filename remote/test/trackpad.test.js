import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createScrollStrip, createTrackpad } from '../trackpad.js';

const finger = (x, y, id = 1) => ({ id, x, y });

/** Asserts commands match, comparing numbers to 6 decimals. */
function same(actual, expected) {
  const round = (c) => Object.fromEntries(Object.entries(c).map(([k, v]) => [k, typeof v === 'number' ? Math.round(v * 1e6) / 1e6 : v]));
  assert.deepEqual(actual.map(round), expected.map(round));
}

test('a touch stops any momentum on the Host', () => {
  const pad = createTrackpad();
  same(pad.start([finger(0, 0)], 0), [{ t: 'x' }]);
});

test('ignores movement inside the 8 px slop, so a tap does not nudge the pointer', () => {
  const pad = createTrackpad();
  pad.start([finger(0, 0)], 0);
  same(pad.move([finger(5, 3)], 50), []);
});

test('moves the pointer with the slow-speed gain', () => {
  const pad = createTrackpad();
  pad.start([finger(0, 0)], 0);
  // 10 px in 100 ms: v = 0.1 px/ms, gain = 1.6 × (1 + 1.2 × 0.1) = 1.792
  same(pad.move([finger(10, 0)], 100), [{ t: 'm', dx: 17.92, dy: 0 }]);
});

test('caps the gain for fast flicks', () => {
  const pad = createTrackpad();
  pad.start([finger(0, 0)], 0);
  // 100 px in 10 ms: v = 10 px/ms, gain = 1.6 × min(6, 13) = 9.6
  same(pad.move([finger(0, 100)], 10), [{ t: 'm', dx: 0, dy: 960 }]);
});

/** One-finger tap at (x, y) from t to t + ms; returns what lifting the finger sent. */
function tap(pad, t, { x = 50, y = 50, ms = 80 } = {}) {
  pad.start([finger(x, y)], t);
  return pad.end([], t + ms);
}

test('a quick tap clicks', () => {
  same(tap(createTrackpad(), 0), [{ t: 'c', b: 0, n: 1 }]);
});

test('a long touch without moving does not click', () => {
  same(tap(createTrackpad(), 0, { ms: 400 }), []);
});

test('a second tap soon after, nearby, double-clicks', () => {
  const pad = createTrackpad();
  tap(pad, 0);
  same(tap(pad, 80 + 200), [{ t: 'c', b: 0, n: 2 }]);
  // ...and a third starts over.
  same(tap(pad, 600), [{ t: 'c', b: 0, n: 1 }]);
});

test('a second tap too late or too far away is a new single click', () => {
  const late = createTrackpad();
  tap(late, 0);
  same(tap(late, 80 + 400), [{ t: 'c', b: 0, n: 1 }]);

  const far = createTrackpad();
  tap(far, 0);
  same(tap(far, 200, { x: 250 }), [{ t: 'c', b: 0, n: 1 }]);
});

const kinds = (cmds) => cmds.map((c) => c.t);

test('holding still, then moving, drags', () => {
  const pad = createTrackpad();
  pad.start([finger(0, 0)], 0);
  same(pad.move([finger(1, 0)], 300), []); // resting inside the slop
  assert.deepEqual(kinds(pad.move([finger(20, 0)], 400)), ['d', 'm']);
  assert.deepEqual(kinds(pad.move([finger(30, 0)], 416)), ['m']);
  same(pad.end([], 500), [{ t: 'u' }]);
});

test('tapping, then touching again and moving, drags', () => {
  const pad = createTrackpad();
  tap(pad, 0);
  pad.start([finger(50, 50)], 150);
  assert.deepEqual(kinds(pad.move([finger(70, 50)], 170)), ['d', 'm']);
  same(pad.end([], 300), [{ t: 'u' }]);
});

test('moving straight away just moves the pointer', () => {
  const pad = createTrackpad();
  pad.start([finger(0, 0)], 0);
  assert.deepEqual(kinds(pad.move([finger(20, 0)], 100)), ['m']);
  same(pad.end([], 200), []);
});

const two = (x1, y1, x2, y2) => [finger(x1, y1, 1), finger(x2, y2, 2)];

test('a two-finger tap right-clicks', () => {
  const pad = createTrackpad();
  pad.start([finger(0, 0)], 0);
  pad.start(two(0, 0, 40, 0), 20);
  same(pad.end([finger(40, 0, 2)], 90), [{ t: 'c', b: 1, n: 1 }]);
  same(pad.end([], 100), []);
});

test('two fingers scroll, and the release velocity goes to the Host for momentum', () => {
  const pad = createTrackpad();
  pad.start(two(0, 0, 40, 0), 0);
  // Centroid moves up 10 px per 16 ms; scroll speed 1.5×.
  same(pad.move(two(0, -10, 40, -10), 16), [{ t: 's', dx: 0, dy: -15 }]);
  same(pad.move(two(0, -20, 40, -20), 32), [{ t: 's', dx: 0, dy: -15 }]);
  // 30 px scrolled over the 16 ms between samples.
  same(pad.end([], 40), [{ t: 'se', vx: 0, vy: -1.875 }]);
});

test('no momentum when the fingers had stopped before lifting, or momentum is off', () => {
  const rested = createTrackpad();
  rested.start(two(0, 0, 40, 0), 0);
  rested.move(two(0, -10, 40, -10), 16);
  rested.move(two(0, -20, 40, -20), 32);
  same(rested.end([], 200), [{ t: 'se', vx: 0, vy: 0 }]);

  const off = createTrackpad({ momentum: false });
  off.start(two(0, 0, 40, 0), 0);
  off.move(two(0, -10, 40, -10), 16);
  off.move(two(0, -20, 40, -20), 32);
  same(off.end([], 40), [{ t: 'se', vx: 0, vy: 0 }]);
});

test('the finger left after a two-finger gesture does not move the pointer', () => {
  const pad = createTrackpad();
  pad.start(two(0, 0, 40, 0), 0);
  pad.move(two(0, -20, 40, -20), 16);
  pad.end([finger(40, -20, 2)], 30);
  same(pad.move([finger(80, -20, 2)], 50), []);
  same(pad.end([], 60), []);
});

test('the scroll strip scrolls vertically with one finger and flicks into momentum', () => {
  const strip = createScrollStrip();
  same(strip.start([finger(0, 100)], 0), [{ t: 'x' }]);
  // Sideways motion is ignored; 1.5× scroll speed.
  same(strip.move([finger(6, 90)], 16), [{ t: 's', dx: 0, dy: -15 }]);
  same(strip.move([finger(9, 80)], 32), [{ t: 's', dx: 0, dy: -15 }]);
  same(strip.end([], 40), [{ t: 'se', vx: 0, vy: -1.875 }]);
});

// ---------- Gestures, following the Mac trackpad settings ----------

/** A new Mac's settings, as the Host pushes them. */
const mac = (fields = {}) => ({
  t: 'tp', pinch: true, rotate: true, smartZoom: true, pages: '2', spaces: 3, missionControl: 3,
  appExpose: 0, showDesktop: true, apps: true, notificationCenter: true, lookUp: true,
  threeFingerDrag: false, followsFingers: true, ...fields,
});
/** Two fingers `r` px either side of (150, 100), turned `deg` degrees clockwise on screen, moved by `dx`. */
const pair = (r, deg = 0, dx = 0) => {
  const a = (deg * Math.PI) / 180;
  return [finger(150 + dx - r * Math.cos(a), 100 - r * Math.sin(a), 1), finger(150 + dx + r * Math.cos(a), 100 + r * Math.sin(a), 2)];
};
/** A pad following `tp`, with two fingers down at 0 and 5 ms. */
function twoDown(tp = mac()) {
  const pad = createTrackpad();
  pad.follow(tp);
  pad.start([pair(50)[0]], 0);
  pad.start(pair(50), 5);
  return pad;
}

test('a pinch waits for the fingers to settle, then sends magnification deltas', () => {
  const pad = twoDown();
  same(pad.move(pair(60), 30), []); // before the 60 ms settle
  same(pad.move(pair(60), 70), []); // decided here; the deltas start from this spread
  same(pad.move(pair(72), 90), [{ t: 'g', g: 'pinch', d: 0.2 }]);
  same(pad.move(pair(72), 100), []); // no change, no frame
});

test('a rotate sends degrees, counter-clockwise positive', () => {
  const pad = twoDown();
  same(pad.move(pair(50, 20), 70), []);
  same(pad.move(pair(50, 30), 90), [{ t: 'g', g: 'rotate', d: -10 }]);
});

test('a Gesture holds until every finger is up, then ends', () => {
  const pad = twoDown();
  pad.move(pair(60), 70);
  pad.move(pair(66), 80);
  same(pad.end([pair(66)[0]], 100), []);
  same(pad.move([finger(10, 10, 1)], 110), []); // the finger left behind moves nothing
  same(pad.end([], 120), [{ t: 'ge', g: 'pinch', ok: true }]);
  // The next touch starts afresh.
  same(pad.start([finger(0, 0)], 400), [{ t: 'x' }]);
});

test('with the Mac trackpad settings, two fingers still scroll, keeping the travel made while settling', () => {
  const pad = twoDown();
  same(pad.move(pair(50, 0, 20), 30), []);
  same(pad.move(pair(50, 0, 25), 70), [{ t: 's', dx: 37.5, dy: 0 }]);
  same(pad.move(pair(50, 0, 29), 80), [{ t: 's', dx: 6, dy: 0 }]);
});

test('a two-finger tap right-clicks at once, and a second one soon after smart-zooms', () => {
  const pad = twoDown();
  same(pad.end([pair(50)[1]], 60), [{ t: 'c', b: 1, n: 1 }]);
  same(pad.end([], 65), []);
  pad.start([pair(50)[0]], 200);
  pad.start(pair(50), 205);
  same(pad.end([pair(50)[1]], 250), [{ t: 'ga', a: 'smartZoom' }]);
  pad.end([], 255);
  // The double-tap is over: the next one right-clicks again.
  pad.start(pair(50), 400);
  same(pad.end([], 450), [{ t: 'c', b: 1, n: 1 }]);
});

test('a second two-finger tap right-clicks again with smart zoom off, or too late', () => {
  const pad = twoDown(mac({ smartZoom: false }));
  pad.end([], 60);
  pad.start(pair(50), 200);
  same(pad.end([], 250), [{ t: 'c', b: 1, n: 1 }]);

  const late = twoDown();
  late.end([], 60);
  late.start(pair(50), 400);
  same(late.end([], 450), [{ t: 'c', b: 1, n: 1 }]);
});

test('spreading the fingers sends no Gesture when the Mac has pinch off', () => {
  const pad = twoDown(mac({ pinch: false }));
  same(pad.move(pair(60), 70), []);
  same(pad.move(pair(72), 90), []);
});

test('three fingers send nothing yet with the Mac trackpad settings', () => {
  const pad = twoDown();
  same(pad.start([...pair(50), finger(150, 200, 3)], 10), []);
  same(pad.move([...pair(50, 0, 40), finger(190, 200, 3)], 100), []);
  same(pad.end(pair(50, 0, 40), 120), []);
  same(pad.end([], 130), []);
});

test('without the Mac trackpad settings, a pinch is just two fingers, as in v1', () => {
  const pad = createTrackpad();
  pad.start(pair(50), 0);
  same(pad.move(pair(60), 70), []);
  same(pad.end([], 100), [{ t: 'c', b: 1, n: 1 }]);
});
