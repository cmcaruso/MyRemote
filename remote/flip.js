/**
 * Upside down: tells from the phone's tilt when it's held upside down, mic toward the mouth, so the
 * Remote can turn itself round (iPhones with Face ID never rotate a page upside down).
 *
 * Pure: every call gets `beta` from `deviceorientation`, the front-to-back tilt in degrees, about +90
 * upright and -90 upside down, and returns whether the Remote should be upside down. It turns only after
 * the tilt has stayed past `threshold` for `holdMs`, and between the thresholds (flat on a table, say)
 * it stays as it is.
 */

export const FLIP = Object.freeze({
  threshold: 30, // degrees past flat
  holdMs: 400,
});

export function createFlip({ threshold = FLIP.threshold, holdMs = FLIP.holdMs } = {}) {
  let flipped = false;
  let since = null; // when the tilt first pointed the other way

  return {
    get flipped() {
      return flipped;
    },
    /** @param {number | null} beta degrees @param {number} t ms */
    update(beta, t) {
      const other = beta !== null && (flipped ? beta > threshold : beta < -threshold);
      if (!other) since = null;
      else if (since === null) since = t;
      else if (t - since >= holdMs) {
        flipped = !flipped;
        since = null;
      }
      return flipped;
    },
  };
}
