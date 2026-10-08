import { test } from 'node:test';
import assert from 'node:assert/strict';
import { effective, gestureFoot, gestureRows } from '../gestures.js';

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
