import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classifyMany, classifyTwo, completes, dockProgress, effective, fromRightEdge, gestureFoot, gestureRows, pinchDelta, rotateDelta, shape } from '../gestures.js';

/** A new Mac's settings, as the Host pushes them. */
const tp = (fields = {}) => ({
  t: 'tp', pinch: true, rotate: true, smartZoom: true, pages: '2', spaces: 3, missionControl: 3,
  appExpose: 0, showDesktop: true, apps: true, notificationCenter: true, lookUp: true,
  threeFingerDrag: false, followsFingers: true, ...fields,
});

test('three-finger drag pushes the three-finger swipes to four fingers', () => {
  const s = effective(tp({ threeFingerDrag: true, appExpose: 3 }));
  assert.deepEqual([s.spaces, s.missionControl, s.appExpose], [4, 4, 4]);
  assert.deepEqual(effective(tp({ threeFingerDrag: true, spaces: 0 })).spaces, 0);
  assert.deepEqual(effective(tp()).spaces, 3);
});

test('three-finger drag leaves swiping between pages only its two-finger way', () => {
  assert.equal(effective(tp({ threeFingerDrag: true, pages: '2or3', spaces: 4 })).pages, '2');
  assert.equal(effective(tp({ threeFingerDrag: true, pages: '3', spaces: 4 })).pages, 'off');
  assert.equal(effective(tp({ threeFingerDrag: true })).pages, '2');
  assert.equal(effective(tp({ pages: '3' })).pages, '3');
});

test('lists the 12 Gesture settings by their Mac names and in the Mac’s order', () => {
  assert.deepEqual(gestureRows(tp()), [
    ['Look up & data detectors', 'Tap with 3 fingers'],
    ['Three-finger drag', 'Off'],
    ['Zoom in or out', 'On'],
    ['Smart zoom', 'On'],
    ['Rotate', 'On'],
    ['Swipe between pages', '2 fingers'],
    ['Swipe between full-screen apps', '3 fingers'],
    ['Notification Center', 'On'],
    ['Mission Control', '3 fingers'],
    ['App Exposé', 'Off'],
    ['Show Desktop', 'On'],
    ['Apps', 'On'],
  ]);
});

test('shows each value the Mac can have', () => {
  const rows = (fields) => Object.fromEntries(gestureRows(tp(fields)));
  assert.equal(rows({ lookUp: false })['Look up & data detectors'], 'Off');
  assert.equal(rows({ pages: '3' })['Swipe between pages'], '3 fingers');
  assert.equal(rows({ pages: '2or3' })['Swipe between pages'], '2 or 3 fingers');
  assert.equal(rows({ pages: 'off' })['Swipe between pages'], 'Off');
  assert.equal(rows({ missionControl: 4 })['Mission Control'], '4 fingers');
  assert.equal(rows({ spaces: 0 })['Swipe between full-screen apps'], 'Off');
  assert.equal(rows({ threeFingerDrag: true })['Mission Control'], '4 fingers');
});

test('no rows before the first snapshot', () => {
  assert.deepEqual(gestureRows(null), []);
});

test('the footnote says when the Dock Gestures happen at once', () => {
  const foot = 'Gestures follow the Mac’s trackpad settings. Change them in System Settings → Trackpad on the Mac.';
  assert.equal(gestureFoot(null), foot);
  assert.equal(gestureFoot(tp()), foot);
  assert.equal(gestureFoot(tp({ followsFingers: false })),
    `${foot} On this version of macOS, Mission Control, App Exposé, Spaces, Show Desktop and Apps happen at once instead of following your fingers.`);
});

const f = (id, x, y) => ({ id, x, y });
/** Two fingers `r` px either side of (150, 100), turned `deg` degrees clockwise on screen. */
const pair = (r, deg = 0) => {
  const a = (deg * Math.PI) / 180;
  return [f(1, 150 - r * Math.cos(a), 100 - r * Math.sin(a)), f(2, 150 + r * Math.cos(a), 100 + r * Math.sin(a))];
};
const close = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, `${a} ≉ ${b}`);

test('a shape is the centroid, the mean spread and the angle between the first two fingers', () => {
  const s = shape([f(2, 200, 100), f(1, 100, 100)]); // out of order: sorted by id
  assert.deepEqual(s.c, { x: 150, y: 100 });
  assert.equal(s.spread, 50);
  assert.equal(s.angle, 0);
  assert.equal(s.n, 2);
});

test('spreading the fingers is a pinch, and its delta is the change in magnification', () => {
  const base = shape(pair(50));
  assert.equal(classifyTwo(base, shape(pair(55)), tp(), 8), null); // 5 px: inside the slop
  assert.equal(classifyTwo(base, shape(pair(60)), tp(), 8), 'pinch');
  assert.equal(classifyTwo(base, shape(pair(40)), tp(), 8), 'pinch'); // closing too
  close(pinchDelta(shape(pair(50)), shape(pair(60))), 0.2);
});

test('turning the fingers is a rotate, counter-clockwise positive', () => {
  const base = shape(pair(50));
  assert.equal(classifyTwo(base, shape(pair(50, 5)), tp(), 8), null); // 4 px round: inside the slop
  assert.equal(classifyTwo(base, shape(pair(50, 20)), tp(), 8), 'rotate');
  close(rotateDelta(base, shape(pair(50, 20))), -20); // clockwise on screen
  close(rotateDelta(base, shape(pair(50, -5))), 5);
});

test('a pinch with one finger still is a pinch, however far apart the fingers are', () => {
  for (const gap of [60, 120, 200]) {
    const base = shape([f(1, 100, 300), f(2, 100 + gap, 300 - gap)]);
    const now = shape([f(1, 100, 300), f(2, 112 + gap, 288 - gap)]); // the index finger 17 px out
    assert.equal(classifyTwo(base, now, tp(), 8), 'pinch', `${gap} px`);
  }
});

test('turning one finger round the other is a rotate', () => {
  const base = shape([f(1, 100, 300), f(2, 250, 300)]);
  assert.equal(classifyTwo(base, shape([f(1, 100, 300), f(2, 250, 280)]), tp(), 8), 'rotate');
});

test('two fingers moving together scroll, even when their gap wobbles', () => {
  const base = shape(pair(50));
  // Both down 20 px; one goes 6 px further.
  const now = shape([f(1, 100, 120), f(2, 200, 126)]);
  assert.equal(classifyTwo(base, now, tp(), 8), 'scroll');
});

test('a rotate across ±180° does not jump', () => {
  close(rotateDelta(shape(pair(50, 170)), shape(pair(50, -170))), -20);
});

test('moving the fingers together past the slop is a scroll', () => {
  const base = shape(pair(50));
  const moved = (dx) => shape(pair(50).map((p) => ({ ...p, x: p.x + dx })));
  assert.equal(classifyTwo(base, moved(5), tp(), 8), null);
  assert.equal(classifyTwo(base, moved(12), tp(), 8), 'scroll');
});

test('pinch and rotate count only when the Mac has them on', () => {
  const base = shape(pair(50));
  assert.equal(classifyTwo(base, shape(pair(60)), tp({ pinch: false }), 8), null);
  assert.equal(classifyTwo(base, shape(pair(50, 20)), tp({ rotate: false }), 8), null);
  // Moving as well, they scroll.
  const moved = shape([f(1, 100, 100), f(2, 240, 100)]); // one finger 40 px out: the centre moves 20
  assert.equal(classifyTwo(base, moved, tp({ pinch: false }), 8), 'scroll');
});

test('two fingers swipe in from the right edge when the right-hand one lands within 32 px of it and they go left', () => {
  const pad = { width: 320 };
  const at = (x, dx = 0, dy = 0) => shape([f(1, x - 45 + dx, 200 + dy), f(2, x + dx, 205 + dy)]);
  assert.equal(at(300).right, 300);
  assert.equal(fromRightEdge(at(300), at(300, -20, 4), pad), true);
  assert.equal(fromRightEdge(at(280), at(280, -20, 4), pad), false); // 40 px in
  assert.equal(fromRightEdge(at(300), at(300, 20), pad), false); // going right
  assert.equal(fromRightEdge(at(300), at(300, -10, 20), pad), false); // mostly down
});

// ---------- The Dock Gestures ----------

const three = (dx = 0, dy = 0) => shape([f(1, 160 + dx, 200 + dy), f(2, 200 + dx, 190 + dy), f(3, 240 + dx, 200 + dy)]);
const four = (r, dx = 0, dy = 0) => shape([f(1, 200 - r + dx, 200 - r + dy), f(2, 200 + r + dx, 200 - r + dy), f(3, 200 + r + dx, 200 + r + dy), f(4, 200 - r + dx, 200 + r + dy)]);

test('three fingers swipe once they travel 30 px, each way to its Gesture', () => {
  const on = tp({ appExpose: 3 });
  assert.equal(classifyMany(three(), three(0, -25), on), null);
  assert.equal(classifyMany(three(), three(0, -35), on), 'missionControl');
  assert.equal(classifyMany(three(), three(0, 35), on), 'appExpose');
  assert.equal(classifyMany(three(), three(35, 5), on), 'spaces');
  assert.equal(classifyMany(three(), three(-35, 5), on), 'spaces');
});

test('three fingers sideways swipe between pages when the Mac uses three for that', () => {
  const pages = tp({ pages: '3', spaces: 4 });
  assert.equal(classifyMany(three(), three(35, 5), pages), 'pages');
  assert.equal(classifyMany(three(), three(-35, 5), tp({ pages: '2or3', spaces: 4 })), 'pages');
  assert.equal(classifyMany(three(), three(0, -35), pages), 'missionControl'); // up is still Mission Control
  assert.equal(classifyMany(three(), three(35, 5), tp({ pages: '2', spaces: 0 })), null); // two fingers only
  assert.equal(classifyMany(four(40), four(40, 40), pages), 'spaces');
});

test('a swipe for a finger count the Mac does not use is nothing', () => {
  assert.equal(classifyMany(four(40), four(40, 0, -40), tp()), null); // swipes take three
  assert.equal(classifyMany(four(40), four(40, 0, -40), tp({ missionControl: 4 })), 'missionControl');
  assert.equal(classifyMany(three(), three(0, 40), tp()), null); // App Exposé off
});

test('four or five fingers pinch for Apps and spread for Show Desktop', () => {
  assert.equal(classifyMany(four(60), four(45), tp()), 'apps');
  assert.equal(classifyMany(four(60), four(55), tp()), null); // 8 %: not yet
  assert.equal(classifyMany(four(50), four(65), tp()), 'showDesktop');
  assert.equal(classifyMany(four(60), four(45), tp({ apps: false })), null);
  assert.equal(classifyMany(three(), shape([f(1, 170, 200), f(2, 200, 195), f(3, 230, 200)]), tp()), null); // three can't
});

test('progress is half the pad for a swipe, and half the spread again for a pinch', () => {
  const pad = { width: 300, height: 400 };
  close(dockProgress('missionControl', three(), three(0, -100), pad, 0), 0.5);
  close(dockProgress('appExpose', three(), three(0, 100), pad, 0), 0.5);
  close(dockProgress('spaces', three(), three(-75, 0), pad, 0), -0.5);
  close(dockProgress('pages', three(), three(75, 0), pad, 0), 0.5);
  const s = four(60).spread;
  close(dockProgress('apps', four(60), four(45), pad, s), 0.5);
  close(dockProgress('showDesktop', four(60), four(75), pad, s), 0.5);
});

test('a Dock Gesture completes at a quarter, 20 % spread for a pinch, or on a flick', () => {
  assert.equal(completes('missionControl', 0.24, 0), false);
  assert.equal(completes('missionControl', 0.25, 0), true);
  assert.equal(completes('missionControl', 0.1, 0.003), true);
  assert.equal(completes('missionControl', 0.4, -0.003), true); // flicked back, but past a quarter
  assert.equal(completes('missionControl', -0.3, 0), false);
  assert.equal(completes('apps', 0.3, 0), false);
  assert.equal(completes('apps', 0.4, 0), true);
  assert.equal(completes('spaces', -0.3, 0), true);
  assert.equal(completes('spaces', -0.1, -0.003), true);
  assert.equal(completes('spaces', -0.1, 0.003), false); // flicked back toward where it started
  assert.equal(completes('pages', -0.3, 0), true);
  assert.equal(completes('pages', 0.1, 0.003), true);
});
