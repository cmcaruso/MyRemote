/**
 * Trackpad gestures: turns touches on the pad into commands for the Host.
 *
 * Pure and timer-free: every call gets the touches currently down and the event time, and returns the
 * commands to send. Motion and scroll come out as `{ t: 'm' | 's', dx, dy }` for the sender to
 * coalesce; everything else is a discrete command in the Host's wire format.
 */

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

  /** idle | one (one finger) | two (two fingers, not scrolling yet) | scroll | done (wait for all fingers up) */
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

  return {
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
      } else if (touches.length >= 2 && (mode === 'idle' || (mode === 'one' && !dragging))) {
        mode = 'two';
        twoStart = t;
        centroid = center(touches);
      }
      return out;
    },

    /** @param {Touch[]} touches @param {number} t */
    move(touches, t) {
      const out = [];
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
        if (t - twoStart < p.tapMs * 1.5) out.push({ t: 'c', b: 1, n: 1 });
        mode = left ? 'done' : 'idle';
      } else if (mode === 'scroll') {
        out.push({ t: 'se', ...flick.release(t) });
        mode = left ? 'done' : 'idle';
      } else if (mode === 'done' && left === 0) {
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
