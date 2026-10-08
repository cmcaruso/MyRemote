/**
 * Upside down: tells from the phone's tilt when it's held upside down, mic toward the mouth, so the
 * Remote can turn itself round (iPhones with Face ID never rotate a page upside down).
 *
 * Pure: every call gets `beta` and `gamma` from `deviceorientation`, the front-to-back and left-to-right
 * tilt in degrees, and returns whether the Remote should be upside down. From them it finds which way is
 * up across the screen: toward its top, its bottom, or a side. It turns round once the top has pointed down
 * for `holdMs`, at least `threshold` past flat, and back once it has pointed up or to a side as long (on its
 * side, in landscape, `beta` alone swings wildly). Flat on a table it stays as it is.
 */

export const FLIP = Object.freeze({
  threshold: 30, // degrees past flat
  holdMs: 400,
});

const RAD = Math.PI / 180;

/** Which way the phone's top points: 'up', 'down', 'side', or null when it's near flat. */
function facing(beta, gamma, lean) {
  if (beta === null || gamma === null) return null;
  // Up, seen on the screen's plane: x toward its right edge, y toward its top.
  const x = -Math.sin(gamma * RAD) * Math.cos(beta * RAD);
  const y = Math.sin(beta * RAD);
  if (Math.hypot(x, y) < lean) return null;
  if (Math.abs(y) <= Math.abs(x)) return 'side';
  return y > 0 ? 'up' : 'down';
}

export function createFlip({ threshold = FLIP.threshold, holdMs = FLIP.holdMs } = {}) {
  const lean = Math.sin(threshold * RAD);
  let flipped = false;
  let since = null; // when the top first pointed the other way

  return {
    get flipped() {
      return flipped;
    },
    /** @param {number | null} beta degrees @param {number | null} gamma degrees @param {number} t ms */
    update(beta, gamma, t) {
      const way = facing(beta, gamma, lean);
      const other = flipped ? way === 'up' || way === 'side' : way === 'down';
      if (!other) since = null;
      else if (since === null) since = t;
      else if (t - since >= holdMs) {
        flipped = !flipped;
        since = null;
      }
      return flipped;
    },
    /** The right way up again, as when iOS has just rotated the page: it does that only for a phone held so. */
    reset() {
      flipped = false;
      since = null;
    },
  };
}

/**
 * How far to turn the Remote clockwise, in degrees, to show it upside down, from the screen's orientation
 * angle (0 portrait, 90 turned left, 270 turned right). Turned over through landscape, iOS leaves the page
 * in landscape, so the turn is a quarter one way or the other; an iPad already shows it upside down.
 */
export function turnFor(angle) {
  return { 0: 180, 90: 90, 180: 0, 270: -90 }[((angle % 360) + 360) % 360] ?? 0;
}

/**
 * Where a point on the page is in a turned surface's own pixels, from the surface's box on the page
 * (`getBoundingClientRect`, so already turned).
 */
export function unturn(x, y, box, turn) {
  const dx = x - box.left;
  const dy = y - box.top;
  if (turn === 180) return { x: box.width - dx, y: box.height - dy };
  if (turn === 90) return { x: dy, y: box.width - dx };
  if (turn === -90) return { x: box.height - dy, y: dx };
  return { x: dx, y: dy };
}
