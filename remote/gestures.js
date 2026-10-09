/**
 * Gestures: what the Mac trackpad settings the Host pushes ({t:'tp',…}) mean for the Remote's trackpad.
 *
 * Pure functions, no DOM: unit-tested with `node --test`.
 */

/**
 * The snapshot as the Remote follows it. Three-finger drag takes three fingers, so the swipes that
 * would use three take four, as on the Mac.
 * @param {object} tp the Host's snapshot
 */
export function effective(tp) {
  if (!tp.threeFingerDrag) return tp;
  const four = (n) => (n === 3 ? 4 : n);
  return { ...tp, spaces: four(tp.spaces), missionControl: four(tp.missionControl), appExpose: four(tp.appExpose) };
}

const onOff = (on) => (on ? 'On' : 'Off');
const fingers = (n) => (n ? `${n} fingers` : 'Off');
const PAGES = { 2: '2 fingers', 3: '3 fingers', '2or3': '2 or 3 fingers', off: 'Off' };

/**
 * The Settings sheet's Gestures rows: the Mac's own names and order (System Settings → Trackpad),
 * each with its value. None until the first snapshot.
 * @param {object | null} tp
 * @returns {[string, string][]}
 */
export function gestureRows(tp) {
  if (!tp) return [];
  const s = effective(tp);
  return [
    // The Remote taps with three fingers even when the Mac looks up by Force Click.
    ['Look up & data detectors', s.lookUp ? 'Tap with 3 fingers' : 'Off'],
    ['Three-finger drag', onOff(s.threeFingerDrag)],
    ['Zoom in or out', onOff(s.pinch)],
    ['Smart zoom', onOff(s.smartZoom)],
    ['Rotate', onOff(s.rotate)],
    ['Swipe between pages', PAGES[s.pages] ?? 'Off'],
    ['Swipe between full-screen apps', fingers(s.spaces)],
    ['Notification Center', onOff(s.notificationCenter)],
    ['Mission Control', fingers(s.missionControl)],
    ['App Exposé', fingers(s.appExpose)],
    ['Show Desktop', onOff(s.showDesktop)],
    ['Apps', onOff(s.apps)],
  ];
}

/**
 * The footnote under the Gestures rows; it also says when the Dock Gestures happen at once.
 * @param {object | null} tp
 */
export function gestureFoot(tp) {
  const foot = 'Gestures follow the Mac’s trackpad settings. Change them in System Settings → Trackpad on the Mac.';
  if (!tp || tp.followsFingers) return foot;
  return `${foot} On this version of macOS, Mission Control, App Exposé, Spaces, Show Desktop and Apps happen at once instead of following your fingers.`;
}

/** Recognition timings, from the gestures-feel prototype (#45). */
export const GESTURE = Object.freeze({
  settleMs: 60, // after the finger count last changed, before deciding
  dblMs: 300, // window for the second two-finger tap of a smart zoom
});

const deg = (r) => (r * 180) / Math.PI;
/** An angle wrapped to −π…π. */
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));

/**
 * Where the fingers are as a group: centroid, spread (mean distance from it) and the angle from the
 * first finger to the second, in id order so it doesn't flip.
 * @param {{ id: number, x: number, y: number }[]} touches
 */
export function shape(touches) {
  const list = [...touches].sort((a, b) => a.id - b.id);
  const n = list.length;
  const c = { x: list.reduce((sum, f) => sum + f.x, 0) / n, y: list.reduce((sum, f) => sum + f.y, 0) / n };
  const spread = list.reduce((sum, f) => sum + Math.hypot(f.x - c.x, f.y - c.y), 0) / n;
  const angle = n >= 2 ? Math.atan2(list[1].y - list[0].y, list[1].x - list[0].x) : 0;
  return { c, spread, angle, n };
}

/**
 * What two fingers are doing since `base`: pinch, rotate, scroll, or null while undecided. Their motion
 * splits into how far the centre moved, how far each finger moved toward or away from it, and how far
 * round it, all in px; once any passes the slop, the biggest decides. A pinch with one finger still moves
 * the centre as much as the spread, so the spread only has to match half the centre's travel. Pinch and
 * rotate count only when the Mac has them on; otherwise the fingers scroll.
 * @param {ReturnType<typeof shape>} base @param {ReturnType<typeof shape>} now @param {object} tp @param {number} slop
 */
export function classifyTwo(base, now, tp, slop) {
  const travel = Math.hypot(now.c.x - base.c.x, now.c.y - base.c.y);
  const spread = Math.abs(now.spread - base.spread);
  const turn = Math.abs(wrap(now.angle - base.angle)) * base.spread;
  if (Math.max(travel, spread, turn) <= slop) return null;
  if (tp.pinch && spread >= turn && spread >= travel / 2) return 'pinch';
  if (tp.rotate && turn > spread && turn >= travel / 2) return 'rotate';
  return travel > slop ? 'scroll' : null;
}

/** A pinch's delta: the change in magnification, as AppKit uses it (0.04 = 4 % larger). */
export const pinchDelta = (prev, now) => (prev.spread > 0 ? now.spread / prev.spread - 1 : 0);

/** A rotate's delta in degrees, counter-clockwise positive (the page's y points down). */
export const rotateDelta = (prev, now) => -deg(wrap(now.angle - prev.angle));
