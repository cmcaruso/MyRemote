/**
 * Trackpad gestures: turns touches on the pad into commands for the Host.
 *
 * Pure and timer-free: every call gets the touches currently down and the event time, and returns the
 * commands to send. Motion and scroll come out as `{ t: 'm' | 's', dx, dy }` and Gesture deltas as
 * `{ t: 'g', g, d }` for the sender to coalesce; everything else is a discrete command in the Host's
 * wire format.
 */

import { GESTURE, classifyTwo, pinchDelta, rotateDelta, shape } from './gestures.js';

/** Gesture timings and the acceleration curve; v1 defaults from the trackpad-feel prototype. */
export const DEFAULTS = Object.freeze({
  sens: 1.6, // base gain at slow finger speed
  accel: 1.2, // how much speed adds
  exp: 1.0, // curve shape: gain = sens × min(cap, 1 + accel × v^exp), v in px/ms
  cap: 6, // max multiplier over sens
  scroll: 1.5, // scroll speed multiplier
  momentum: true, // Host coasts after a two-finger flick
  slop: 8, // px a finger can wander and still be a tap
  tapMs: 200, // longest tap
  holdMs: 350, // hold this long, then move, to drag
  dblMs: 280, // window for the second tap of a double-tap (or tap-then-drag)
});

/** @typedef {{ id: number, x: number, y: number }} Touch */

const center = (touches) => ({
  x: touches.reduce((sum, f) => sum + f.x, 0) / touches.length,
  y: touches.reduce((sum, f) => sum + f.y, 0) / touches.length,
});

/** Tracks recent scroll deltas to work out the velocity a flick is released at. */
function createFlick(p) {
  let samples = []; // { t, dx, dy }, the last 80 ms
  return {
    add(t, dx, dy) {
      samples.push({ t, dx, dy });
      samples = samples.filter((s) => t - s.t < 80);
    },
    /** Release velocity in px/ms; zero if the fingers had stopped, or momentum is off. */
    release(t) {
      const recent = samples.filter((s) => t - s.t < 80);
      samples = [];
      if (!p.momentum || recent.length < 2 || t - recent[recent.length - 1].t >= 40) return { vx: 0, vy: 0 };
      const span = Math.max(recent[recent.length - 1].t - recent[0].t, 8);
      return {
        vx: recent.reduce((sum, s) => sum + s.dx, 0) / span,
        vy: recent.reduce((sum, s) => sum + s.dy, 0) / span,
      };
    },
  };
}

/** How many Host pixels a finger moving at `v` px/ms covers per pixel: the acceleration curve. */
export const pointerGain = (p, v) => p.sens * Math.min(p.cap, 1 + p.accel * Math.pow(v, p.exp));

/** @param {Partial<typeof DEFAULTS>} [params] */
export function createTrackpad(params = {}) {
  const p = { ...DEFAULTS, ...params };
  const gain = (v) => pointerGain(p, v);

  /**
   * idle | one (one finger) | two (two fingers, undecided) | scroll | pinch | rotate | many (three or more
   * fingers) | done (wait for all fingers up). Pinch, rotate and many come only with the Mac's settings.
   */
  let mode = 'idle';
  let start = null; // first finger at touch-down: { x, y, t }
  let last = null; // last single-finger position: { x, y, t }
  let moved = false; // past the slop
  let secondTap = false; // this touch came soon after a tap, near it
  let lastTap = null; // end of the last single tap: { x, y, t }
  let dragging = false; // left button held by this touch
  let twoStart = 0; // when the second finger landed
  let centroid = null; // last two-finger center
  const flick = createFlick(p);
  let mac = null; // the Mac trackpad settings followed; until they come, v1's two-finger gestures only
  let base = null; // the two fingers' shape when they landed, or when the Gesture last moved
  let lastTwoTap = null; // end of the last two-finger tap, for smart zoom

  return {
    /** Follows the Mac trackpad settings the Host pushed ({t:'tp',…}), or v1's gestures with null. */
    follow(tp) {
      mac = tp;
    },

    /** @param {Touch[]} touches all touches now down @param {number} t event time, ms */
    start(touches, t) {
      const out = mode === 'idle' ? [{ t: 'x' }] : [];
      if (touches.length === 1 && mode === 'idle') {
        const f = touches[0];
        mode = 'one';
        start = { x: f.x, y: f.y, t };
        last = { ...start };
        moved = false;
        dragging = false;
        secondTap = lastTap !== null && t - lastTap.t < p.dblMs && Math.hypot(f.x - lastTap.x, f.y - lastTap.y) < 60;
      } else if (mac && touches.length >= 3 && (mode === 'idle' || mode === 'two' || (mode === 'one' && !dragging))) {
        mode = 'many';
      } else if (touches.length >= 2 && (mode === 'idle' || (mode === 'one' && !dragging))) {
        mode = 'two';
        twoStart = t;
        centroid = center(touches);
        base = shape(touches);
      }
      return out;
    },

    /** @param {Touch[]} touches @param {number} t */
    move(touches, t) {
      const out = [];
      if (mode === 'two' && mac && touches.length >= 2) {
        // Wait for the fingers to settle, then decide; a scroll keeps the travel since they landed.
        if (t - twoStart < GESTURE.settleMs) return out;
        const kind = classifyTwo(base, shape(touches), mac, p.slop);
        if (kind === 'pinch' || kind === 'rotate') {
          mode = kind;
          base = shape(touches); // from here, so the content doesn't jump by the threshold
          return out;
        }
        if (kind !== 'scroll') return out;
        mode = 'scroll';
      }
      if (mode === 'one' && touches.length === 1) {
        const f = touches[0];
        if (!moved && Math.hypot(f.x - start.x, f.y - start.y) > p.slop) {
          moved = true;
          // Leaving the slop after holding still, or on the touch right after a tap, starts a drag.
          // (Timer-free: a hold is only noticed once the finger moves.)
          if (t - start.t >= p.holdMs || secondTap) {
            dragging = true;
            out.push({ t: 'd' });
          }
        }
        if (moved) {
          const dx = f.x - last.x, dy = f.y - last.y;
          const g = gain(Math.hypot(dx, dy) / Math.max(t - last.t, 4));
          out.push({ t: 'm', dx: dx * g, dy: dy * g });
        }
        last = { x: f.x, y: f.y, t };
      } else if ((mode === 'pinch' || mode === 'rotate') && touches.length >= 2) {
        const now = shape(touches);
        // A finger lifted or came back: carry on from the new shape.
        const d = now.n !== base.n ? 0 : mode === 'pinch' ? pinchDelta(base, now) : rotateDelta(base, now);
        if (d !== 0) out.push({ t: 'g', g: mode, d });
        base = now;
      } else if ((mode === 'two' || mode === 'scroll') && touches.length >= 2) {
        const c = center(touches);
        const dx = c.x - centroid.x, dy = c.y - centroid.y;
        if (mode === 'two' && Math.hypot(dx, dy) > p.slop) mode = 'scroll';
        if (mode === 'scroll') {
          // Natural direction: the content follows the fingers.
          const sx = dx * p.scroll, sy = dy * p.scroll;
          out.push({ t: 's', dx: sx, dy: sy });
          flick.add(t, sx, sy);
          centroid = c;
        }
      }
      return out;
    },

    /** @param {Touch[]} touches the touches still down @param {number} t */
    end(touches, t) {
      const out = [];
      const left = touches.length;
      if (mode === 'one') {
        if (left > 0) return out;
        if (dragging) {
          out.push({ t: 'u' });
          lastTap = null;
        } else if (!moved && t - start.t < p.tapMs) {
          out.push({ t: 'c', b: 0, n: secondTap ? 2 : 1 });
          // A double-click ends the sequence; a single tap may be the first of one.
          lastTap = secondTap ? null : { x: start.x, y: start.y, t };
        }
        dragging = false;
        mode = 'idle';
      } else if (mode === 'two') {
        if (t - twoStart < p.tapMs * 1.5) {
          // The right-click goes at once; a second two-finger tap soon after smart-zooms instead.
          if (mac?.smartZoom && lastTwoTap !== null && t - lastTwoTap < GESTURE.dblMs) {
            out.push({ t: 'ga', a: 'smartZoom' });
            lastTwoTap = null;
          } else {
            out.push({ t: 'c', b: 1, n: 1 });
            lastTwoTap = t;
          }
        }
        mode = left ? 'done' : 'idle';
      } else if (mode === 'pinch' || mode === 'rotate') {
        // The Gesture holds until every finger is up.
        if (left === 0) {
          out.push({ t: 'ge', g: mode, ok: true });
          mode = 'idle';
        }
      } else if (mode === 'scroll') {
        out.push({ t: 'se', ...flick.release(t) });
        mode = left ? 'done' : 'idle';
      } else if ((mode === 'done' || mode === 'many') && left === 0) {
        mode = 'idle';
      }
      return out;
    },
  };
}

/** The scroll strip beside the pad: one finger, vertical scrolling only. */
export function createScrollStrip(params = {}) {
  const p = { ...DEFAULTS, ...params };
  const flick = createFlick(p);
  let y = null; // last finger y, null when no finger is down

  return {
    /** @param {Touch[]} touches @param {number} t */
    start(touches, t) {
      if (y !== null) return [];
      y = touches[0].y;
      return [{ t: 'x' }];
    },
    /** @param {Touch[]} touches @param {number} t */
    move(touches, t) {
      if (y === null) return [];
      const dy = (touches[0].y - y) * p.scroll;
      y = touches[0].y;
      flick.add(t, 0, dy);
      return [{ t: 's', dx: 0, dy }];
    },
    /** @param {Touch[]} touches @param {number} t */
    end(touches, t) {
      if (y === null || touches.length > 0) return [];
      y = null;
      return [{ t: 'se', ...flick.release(t) }];
    },
  };
}
