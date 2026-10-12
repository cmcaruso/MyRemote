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

/** Two fingers 45 px apart, the right-hand one at `x` on a 320 px pad, moved by `dx`, `dy`. */
const edgePair = (x, dx = 0, dy = 0) => [finger(x - 45 + dx, 200 + dy, 1), finger(x + dx, 205 + dy, 2)];

test('two fingers swiping left in from the right edge open Notification Center once', () => {
  const pad = twoDown();
  pad.end([], 120); // a two-finger tap first: right-click
  pad.start([edgePair(305)[0]], 500);
  pad.start(edgePair(305), 505);
  same(pad.move(edgePair(305, -20, 3), 570), [{ t: 'ga', a: 'notificationCenter' }]);
  same(pad.move(edgePair(305, -60, 3), 590), []);
  same(pad.end([], 700), []);
});

test('from the edge, a swipe the Mac has off, or one going right, scrolls', () => {
  const off = twoDown(mac({ notificationCenter: false }));
  off.end([], 120);
  off.start(edgePair(305), 500);
  same(off.move(edgePair(305, -20), 570), [{ t: 's', dx: -30, dy: 0 }]);
  const right = twoDown();
  right.end([], 120);
  right.start(edgePair(305), 500);
  same(right.move(edgePair(305, 10), 570), [{ t: 's', dx: 15, dy: 0 }]);
});

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

/** Three fingers in a row at (200, 200), moved by `dx`, `dy`. */
const trio = (dx = 0, dy = 0) => [finger(160 + dx, 200 + dy, 1), finger(200 + dx, 190 + dy, 2), finger(240 + dx, 200 + dy, 3)];
/** Four fingers on a square of half-side `r` round (200, 200). */
const quad = (r) => [finger(200 - r, 200 - r, 1), finger(200 + r, 200 - r, 2), finger(200 + r, 200 + r, 3), finger(200 - r, 200 + r, 4)];
/** A 400 × 400 pad following `tp`, with `fingers` landing one by one from 0 ms. */
function manyDown(fingers, tp = mac()) {
  const pad = createTrackpad();
  pad.follow(tp);
  pad.resize(400, 400);
  fingers.forEach((_, i) => pad.start(fingers.slice(0, i + 1), 2 * i));
  return pad;
}

test('three fingers tapping look up, and only a quick, still tap of three', () => {
  const tap = (tp, fingers = trio(), lift = 150) => {
    const pad = manyDown(fingers, tp);
    pad.move(fingers, 80);
    return pad.end([], lift);
  };
  same(tap(mac()), [{ t: 'ga', a: 'lookUp' }]);
  same(tap(mac({ lookUp: false })), []);
  same(tap(mac(), trio(), 400), []); // held too long
  same(tap(mac(), quad(40)), []); // four fingers
  const moved = manyDown(trio());
  moved.move(trio(0, 20), 40); // under the settle, but past the slop
  same(moved.end([], 150), []);
});

test('a three-finger tap lifted a finger at a time still looks up once', () => {
  const pad = manyDown(trio());
  same(pad.end(trio().slice(1), 120), []);
  same(pad.end(trio().slice(2), 125), []);
  same(pad.end([], 130), [{ t: 'ga', a: 'lookUp' }]);
});

test('a three-finger swipe up follows the fingers into Mission Control, half the pad being all the way', () => {
  const pad = manyDown(trio());
  same(pad.move(trio(0, -40), 30), []); // before the 60 ms settle
  same(pad.move(trio(0, -40), 70), [{ t: 'g', g: 'missionControl', d: 0.2 }]); // 30 px decides; the Dock catches up
  same(pad.move(trio(0, -60), 80), [{ t: 'g', g: 'missionControl', d: 0.1 }]);
  // Released slowly at 30 %: it completes.
  same(pad.end(trio(0, -60).slice(0, 2), 300), []);
  same(pad.end([], 310), [{ t: 'ge', g: 'missionControl', ok: true }]);
});

test('a short swipe released slowly springs back', () => {
  const pad = manyDown(trio());
  pad.move(trio(0, -40), 70);
  same(pad.end([], 300), [{ t: 'ge', g: 'missionControl', ok: false }]);
});

test('a short swipe flicked on completes', () => {
  const pad = manyDown(trio());
  pad.move(trio(0, -35), 70);
  pad.move(trio(0, -42), 78);
  same(pad.end([], 82), [{ t: 'ge', g: 'missionControl', ok: true }]);
});

test('swiping back past where it started does not complete', () => {
  const pad = manyDown(trio());
  pad.move(trio(0, -40), 70);
  pad.move(trio(0, 20), 200);
  same(pad.end([], 400), [{ t: 'ge', g: 'missionControl', ok: false }]);
});

test('a three-finger swipe sideways moves between Spaces, fingers to the left negative', () => {
  const pad = manyDown(trio());
  same(pad.move(trio(-60, 0), 70), [{ t: 'g', g: 'spaces', d: -0.3 }]);
  same(pad.end([], 300), [{ t: 'ge', g: 'spaces', ok: true }]);
});

test('three fingers swipe between pages: nothing while they move, then back or forward once', () => {
  const tp = mac({ pages: '3', spaces: 4 });
  const back = manyDown(trio(), tp);
  same(back.move(trio(40, 0), 70), []);
  same(back.move(trio(80, 0), 90), []);
  same(back.end([], 300), [{ t: 'ga', a: 'pageBack' }]); // fingers to the right, 40 %
  const forward = manyDown(trio(), tp);
  forward.move(trio(-80, 0), 70);
  same(forward.end([], 300), [{ t: 'ga', a: 'pageForward' }]);
});

test('a short page swipe released slowly does nothing', () => {
  const pad = manyDown(trio(), mac({ pages: '2or3', spaces: 4 }));
  pad.move(trio(40, 0), 70);
  same(pad.end([], 300), []);
});

test('a Dock Gesture the Mac has off does nothing', () => {
  // A new Mac has App Exposé off.
  const pad = manyDown(trio());
  same(pad.move(trio(0, 80), 70), []);
  same(pad.end([], 300), []);
  const on = manyDown(trio(), mac({ appExpose: 3 }));
  same(on.move(trio(0, 40), 70), [{ t: 'g', g: 'appExpose', d: 0.2 }]);
});

test('four fingers pinching in open Apps, and spreading show the desktop', () => {
  const pad = manyDown(quad(60));
  same(pad.move(quad(45), 70), [{ t: 'g', g: 'apps', d: 0.5 }]);
  same(pad.end([], 300), [{ t: 'ge', g: 'apps', ok: true }]);
  const spread = manyDown(quad(50));
  same(spread.move(quad(65), 70), [{ t: 'g', g: 'showDesktop', d: 0.6 }]);
});

test('with three-finger drag on, three fingers moving drag: button down, moves, button up when all lift', () => {
  const pad = manyDown(trio(), mac({ threeFingerDrag: true }));
  same(pad.move(trio(0, 4), 40), []); // inside the slop
  same(pad.move(trio(0, 20), 70), [{ t: 'd' }]);
  // 10 px in 30 ms: v = 1/3 px/ms, gain = 1.6 × (1 + 1.2 / 3) = 2.24
  same(pad.move(trio(10, 20), 100), [{ t: 'm', dx: 22.4, dy: 0 }]);
  same(pad.end(trio(10, 20).slice(1), 120), []);
  same(pad.move(trio(30, 20).slice(1), 130), []); // a finger lifted: carry on from the new centre
  same(pad.end([], 200), [{ t: 'u' }]);
});

test('with three-finger drag on, a three-finger tap still looks up and a sideways swipe drags', () => {
  const tp = mac({ threeFingerDrag: true, pages: '3', spaces: 4 });
  const tap = manyDown(trio(), tp);
  same(tap.end([], 150), [{ t: 'ga', a: 'lookUp' }]);
  const sideways = manyDown(trio(), tp);
  same(sideways.move(trio(60, 0), 70), [{ t: 'd' }]);
  same(sideways.end([], 300), [{ t: 'u' }]);
});

test('without three-finger drag, three fingers moving never press the button', () => {
  const pad = manyDown(trio(), mac({ missionControl: 0 }));
  same(pad.move(trio(0, -60), 70), []);
  same(pad.end([], 300), []);
});

test('with three-finger drag on, the swipes take four fingers', () => {
  const tp = mac({ threeFingerDrag: true });
  const three = manyDown(trio(), tp);
  same(three.move(trio(0, -60), 70), [{ t: 'd' }]); // three fingers drag instead
  const four = manyDown(quad(40), tp);
  same(four.move(quad(40).map((f) => ({ ...f, y: f.y - 40 })), 70), [{ t: 'g', g: 'missionControl', d: 0.2 }]);
});

test('a Dock Gesture holds until every finger is up, without jumping when one lifts', () => {
  const pad = manyDown(trio());
  pad.move(trio(0, -40), 70);
  same(pad.end(trio(0, -40).slice(1), 90), []);
  same(pad.move(trio(0, -40).slice(1), 100), []); // the centre moved because a finger lifted, not the fingers
  same(pad.move(trio(0, -60).slice(1), 110), [{ t: 'g', g: 'missionControl', d: 0.1 }]);
});

test('a finger landing late measures again from there', () => {
  const pad = createTrackpad();
  pad.follow(mac());
  pad.resize(400, 400);
  pad.start(trio().slice(0, 3), 0);
  pad.move(trio(0, -20), 50);
  // A fourth finger lands: four-finger swipes are off on a new Mac, so nothing is decided.
  pad.start([...trio(0, -20), finger(200, 260, 4)], 60);
  same(pad.move([...trio(0, -70), finger(200, 210, 4)], 200), []);
});

test('without the Mac trackpad settings, a pinch is just two fingers, as in v1', () => {
  const pad = createTrackpad();
  pad.start(pair(50), 0);
  same(pad.move(pair(60), 70), []);
  same(pad.end([], 100), [{ t: 'c', b: 1, n: 1 }]);
});
