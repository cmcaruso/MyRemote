/**
 * Gestures: what the Mac trackpad settings the Host pushes ({t:'tp',…}) mean for the Remote's trackpad.
 *
 * Pure functions, no DOM: unit-tested with `node --test`.
 */

/**
 * The snapshot as the Remote follows it. Three-finger drag takes three fingers, so the swipes that
 * would use three take four, as on the Mac, and swiping between pages keeps only its two-finger way.
 * @param {object} tp the Host's snapshot
 */
export function effective(tp) {
  if (!tp.threeFingerDrag) return tp;
  const four = (n) => (n === 3 ? 4 : n);
  const pages = tp.pages === '2or3' ? '2' : tp.pages === '3' ? 'off' : tp.pages;
  return { ...tp, pages, spaces: four(tp.spaces), missionControl: four(tp.missionControl), appExpose: four(tp.appExpose) };
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
  commitPx: 30, // px the fingers travel before a swipe is decided
  pinchRatio: 0.2, // change in spread that makes a 4–5 finger pinch, and completes it
  complete: 0.25, // progress at release that completes a swipe
  flick: 0.002, // progress per ms at release, toward the Gesture, that completes it however far it got
  edgePx: 32, // from the pad's right edge, where two fingers swiping left open Notification Center
});

const deg = (r) => (r * 180) / Math.PI;
/** An angle wrapped to −π…π. */
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));

/**
 * Where the fingers are as a group: centroid, spread (mean distance from it), the angle from the
 * first finger to the second, in id order so it doesn't flip, and the right-hand finger's x.
 * @param {{ id: number, x: number, y: number }[]} touches
 */
export function shape(touches) {
  const list = [...touches].sort((a, b) => a.id - b.id);
  const n = list.length;
  const c = { x: list.reduce((sum, f) => sum + f.x, 0) / n, y: list.reduce((sum, f) => sum + f.y, 0) / n };
  const spread = list.reduce((sum, f) => sum + Math.hypot(f.x - c.x, f.y - c.y), 0) / n;
  const angle = n >= 2 ? Math.atan2(list[1].y - list[0].y, list[1].x - list[0].x) : 0;
  const right = Math.max(...list.map((f) => f.x));
  return { c, spread, angle, n, right };
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

/**
 * Whether two fingers scrolling from `base` to `now` swipe in from the pad's right edge, as for
 * Notification Center: the right-hand one landed within 32 px of it and they move mostly left.
 * @param {ReturnType<typeof shape>} base @param {ReturnType<typeof shape>} now @param {{ width: number }} pad
 */
export function fromRightEdge(base, now, pad) {
  const dx = now.c.x - base.c.x, dy = now.c.y - base.c.y;
  return base.right >= pad.width - GESTURE.edgePx && dx < 0 && Math.abs(dx) > Math.abs(dy);
}

/** A pinch's delta: the change in magnification, as AppKit uses it (0.04 = 4 % larger). */
export const pinchDelta = (prev, now) => (prev.spread > 0 ? now.spread / prev.spread - 1 : 0);

/** A rotate's delta in degrees, counter-clockwise positive (the page's y points down). */
export const rotateDelta = (prev, now) => -deg(wrap(now.angle - prev.angle));

/** The Dock Gestures that are pinches; the others are swipes. */
const PINCHES = new Set(['showDesktop', 'apps']);

/**
 * Which Gesture three to five fingers are doing since `base`, following the Mac trackpad settings,
 * or null while undecided or when the Mac has it off. Four or five fingers pinching in or spreading by
 * 20 % are Apps or Show Desktop; otherwise, once they travel 30 px, a swipe for that many fingers (five
 * swipe as four). Three fingers sideways swipe between pages when the Mac uses three for that, which
 * leaves Spaces to four.
 * @param {ReturnType<typeof shape>} base @param {ReturnType<typeof shape>} now @param {object} tp
 */
export function classifyMany(base, now, tp) {
  const s = effective(tp);
  const dx = now.c.x - base.c.x, dy = now.c.y - base.c.y, travel = Math.hypot(dx, dy);
  const ratio = now.spread / base.spread;
  if (now.n >= 4 && Math.abs(now.spread - base.spread) >= travel / 2) {
    if (ratio <= 1 - GESTURE.pinchRatio) return s.apps ? 'apps' : null;
    if (ratio >= 1 + GESTURE.pinchRatio) return s.showDesktop ? 'showDesktop' : null;
  }
  if (travel < GESTURE.commitPx) return null;
  const fingers = Math.min(now.n, 4);
  if (Math.abs(dx) > Math.abs(dy)) {
    if (s.spaces === fingers) return 'spaces';
    return fingers === 3 && (s.pages === '3' || s.pages === '2or3') ? 'pages' : null;
  }
  if (dy < 0) return s.missionControl === fingers ? 'missionControl' : null;
  return s.appExpose === fingers ? 'appExpose' : null;
}

/** The swipes that go either way, fingers to the right positive: Spaces, and pages (right is back). */
const SIDEWAYS = new Set(['spaces', 'pages']);

/**
 * How far a Gesture of three or more fingers moved between two shapes, in progress: 1.0 is all the way,
 * half the pad of travel for a swipe, half or one and a half times the starting spread for a pinch.
 * Spaces and pages are signed, fingers to the right positive.
 * @param {string} g @param {ReturnType<typeof shape>} from @param {ReturnType<typeof shape>} to
 * @param {{ width: number, height: number }} pad @param {number} spread the spread the pinch started from
 */
export function dockProgress(g, from, to, pad, spread) {
  switch (g) {
    case 'missionControl': return (from.c.y - to.c.y) / (pad.height / 2);
    case 'appExpose': return (to.c.y - from.c.y) / (pad.height / 2);
    case 'spaces': case 'pages': return (to.c.x - from.c.x) / (pad.width / 2);
    case 'showDesktop': return (to.spread - from.spread) / (spread / 2);
    case 'apps': return (from.spread - to.spread) / (spread / 2);
    default: return 0;
  }
}

/**
 * Whether a Gesture of three or more fingers released at `progress`, moving at `speed` progress per ms,
 * completes: a quarter of the way for a swipe, a 20 % change in spread for a pinch, or a flick toward it.
 * Spaces and pages count either way.
 */
export function completes(g, progress, speed) {
  const sign = SIDEWAYS.has(g) ? Math.sign(progress) : 1;
  const p = progress * sign, v = speed * sign;
  if (p <= 0) return false;
  return p >= (PINCHES.has(g) ? GESTURE.pinchRatio * 2 : GESTURE.complete) || v >= GESTURE.flick;
}
