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
