/**
 * The volume slider's model: what level to show, given the Host's pushes and the finger.
 *
 * While the finger is on the slider it shows the finger's level. After release, the Host is still
 * echoing levels sent mid-drag; those are ignored until the Host reports the final level (or a
 * second has passed), so the thumb doesn't jump back.
 */

/** How long after release to wait for the Host to confirm the final level, ms. */
const CONFIRM_MS = 1000;
/** Levels this close count as the same (the Host rounds to 3 decimals). */
const SAME = 0.002;

export function createVolumeSlider() {
  const state = { level: 0, muted: false, settable: true };
  let touching = false;
  let awaiting = null; // { level, until }: released at this level, waiting for the Host to confirm

  return {
    /** What to show: `{ level, muted, settable }`. */
    get state() {
      return { ...state };
    },

    /** A `{ t: 'vol', v, muted, settable }` push from the Host at time `t`. */
    host(push, t) {
      state.muted = push.muted;
      state.settable = push.settable;
      if (touching) return;
      if (awaiting) {
        const confirmed = Math.abs(push.v - awaiting.level) <= SAME;
        if (!confirmed && t < awaiting.until) return;
        awaiting = null;
      }
      state.level = push.v;
    },

    /** The finger is at `level` along the slider; returns the level to send to the Host. */
    touch(level, t) {
      touching = true;
      awaiting = null;
      state.level = Math.min(Math.max(level, 0), 1);
      return state.level;
    },

    /** The finger lifted at time `t`. */
    release(t) {
      touching = false;
      awaiting = { level: state.level, until: t + CONFIRM_MS };
    },
  };
}
