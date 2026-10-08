/**
 * The Phone Mic's encoder: turns the microphone's Float32 blocks into the Host's wire format, binary
 * frames of mono 16-bit little-endian PCM, `chunkMs` long.
 *
 * Pure: `push` gets one block at the AudioContext's rate and returns the frames now complete. The rate is
 * divided by a whole number (48 kHz → 24 kHz, 44.1 kHz → 22.05 kHz) by averaging, which also filters a
 * little; speech needs no more, and it halves what goes over the network.
 */

export const MIC = Object.freeze({
  outRate: 24000, // Hz to aim for; the real rate is `rate` below
  chunkMs: 20, // ms of audio per frame
  maxQueuedMs: 100, // drop frames while the socket holds more than this, so the delay can't grow
});

/** @param {{ inRate: number, outRate?: number, chunkMs?: number }} options */
export function createMicEncoder({ inRate, outRate = MIC.outRate, chunkMs = MIC.chunkMs }) {
  const factor = Math.max(1, Math.round(inRate / outRate));
  const rate = inRate / factor;
  const size = Math.round((rate * chunkMs) / 1000); // samples per frame
  let frame = new DataView(new ArrayBuffer(size * 2));
  let filled = 0; // samples in `frame`
  let sum = 0; // of the input samples averaged so far
  let taken = 0; // how many

  return {
    /** The rate the frames are at, for `/mic?rate=`. */
    rate,
    /** @param {Float32Array} block @returns {ArrayBuffer[]} frames now complete */
    push(block) {
      const out = [];
      for (const sample of block) {
        sum += sample;
        if (++taken < factor) continue;
        const v = Math.max(-1, Math.min(1, sum / factor));
        frame.setInt16(filled * 2, v < 0 ? v * 32768 : v * 32767, true);
        sum = 0;
        taken = 0;
        if (++filled === size) {
          out.push(frame.buffer);
          frame = new DataView(new ArrayBuffer(size * 2));
          filled = 0;
        }
      }
      return out;
    },
  };
}

/** Whether the socket is backed up enough that a new frame would only add delay. */
export const shouldDrop = (bufferedAmount, rate, maxQueuedMs = MIC.maxQueuedMs) =>
  bufferedAmount > (rate * 2 * maxQueuedMs) / 1000;
