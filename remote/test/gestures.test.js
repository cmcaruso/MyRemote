import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classifyTwo, effective, gestureFoot, gestureRows, pinchDelta, rotateDelta, shape } from '../gestures.js';

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
  assert.equal(classifyTwo(base, shape(pair(55)), tp(), 8), null); // 10 %: not yet
  assert.equal(classifyTwo(base, shape(pair(60)), tp(), 8), 'pinch'); // 20 %
  assert.equal(classifyTwo(base, shape(pair(40)), tp(), 8), 'pinch'); // closing too
  close(pinchDelta(shape(pair(50)), shape(pair(60))), 0.2);
});

test('turning the fingers is a rotate, counter-clockwise positive', () => {
  const base = shape(pair(50));
  assert.equal(classifyTwo(base, shape(pair(50, 10)), tp(), 8), null);
  assert.equal(classifyTwo(base, shape(pair(50, 20)), tp(), 8), 'rotate');
  close(rotateDelta(base, shape(pair(50, 20))), -20); // clockwise on screen
  close(rotateDelta(base, shape(pair(50, -5))), 5);
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
});
