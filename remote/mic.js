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

/**
 * The echo guard: what a microphone does to keep a room's speakers from feeding back into it. Played
 * through a room's speakers, the Phone Mic hears itself again; held at the mouth, the voice is far louder
 * than the speakers, so the gate below lets the voice through and turns the rest down, and the howl
 * detector finds the tone a feedback loop rings at, for a notch filter to take out.
 */
export const GUARD = Object.freeze({
  open: 10, // dB over the room's level that opens the gate
  close: 6, // dB over it under which the gate starts to close
  quietest: -55, // dBFS: never opens below this, however quiet the room
  floorRise: 3, // dB per second the room's level estimate creeps up, so a louder room is learned
  hold: 0.25, // s the gate stays open after the voice drops, so word endings aren't cut
  attack: 0.005, // s to open
  release: 0.08, // s to close
  closed: -20, // dB the gate turns the room down by: not silence, which would sound choppy
});

const dB = (power) => 10 * Math.log10(power + 1e-12);

/**
 * A voice gate (downward expander). Pure: `process` gets one block and returns a copy turned down where
 * the gate is closed. It follows the room's level as the quietest it has heard lately.
 * @param {{ rate: number }} options
 */
export function createGate({ rate }, p = GUARD) {
  let floor = Infinity; // the room's level, dBFS; the first block sets it
  let gain = 10 ** (p.closed / 20);
  let held = 0; // seconds of hold left
  const shut = 10 ** (p.closed / 20);
  const up = 1 / (p.attack * rate); // gain change per sample
  const down = (1 - shut) / (p.release * rate);

  return {
    get open() {
      return held > 0;
    },
    /** @param {Float32Array} block @returns {Float32Array} */
    process(block) {
      const seconds = block.length / rate;
      let power = 0;
      for (const s of block) power += s * s;
      const level = dB(power / block.length);
      floor = level < floor ? level : floor + p.floorRise * seconds;
      const over = level - Math.max(floor, p.quietest);
      if (level > p.quietest && over >= p.open) held = p.hold;
      else if (over >= p.close && held > 0) held = p.hold;
      else held = Math.max(0, held - seconds);
      const target = held > 0 ? 1 : shut;
      const out = new Float32Array(block.length);
      for (let i = 0; i < block.length; i++) {
        gain = gain < target ? Math.min(target, gain + up) : Math.max(target, gain - down);
        out[i] = block[i] * gain;
      }
      return out;
    },
  };
}

export const HOWL = Object.freeze({
  low: 150, // Hz: the band feedback is looked for in
  high: 8000,
  peak: 30, // dB a tone must stand above the spectrum's median: feedback is a pure tone, a voice isn't
  loudest: -60, // dBFS the tone must also pass, so a quiet room can't trigger it
  last: 0.4, // s it must ring, steady, before it's called feedback
});

/**
 * Finds feedback: a tone that stands far above everything else and holds its pitch, which a voice
 * doesn't. Pure: `update` gets one magnitude spectrum in dB (an AnalyserNode's) and returns the
 * frequency to notch out, once, or null.
 * @param {{ rate: number, bins: number }} options sample rate, and the spectrum's length (fftSize / 2)
 */
export function createHowlDetector({ rate, bins }, p = HOWL) {
  const hz = rate / 2 / bins; // per bin
  const from = Math.max(1, Math.floor(p.low / hz));
  const to = Math.min(bins - 1, Math.ceil(p.high / hz));
  let ringing = null; // { bin, since }

  return {
    /** @param {Float32Array} spectrum dB per bin @param {number} t seconds */
    update(spectrum, t) {
      let top = from;
      for (let i = from; i <= to; i++) if (spectrum[i] > spectrum[top]) top = i;
      const band = Array.from(spectrum.subarray(from, to + 1)).sort((a, b) => a - b);
      const median = band[band.length >> 1];
      if (spectrum[top] < p.loudest || spectrum[top] - median < p.peak) {
        ringing = null;
        return null;
      }
      if (!ringing || Math.abs(ringing.bin - top) > 1) {
        ringing = { bin: top, since: t };
        return null;
      }
      if (t - ringing.since < p.last) return null;
      ringing = null;
      return top * hz;
    },
  };
}

/**
 * Where a new notch goes among `notches` (their frequencies, null when free): deeper on one already
 * within 3% of `frequency`, else the first free one, else the oldest. Returns its index and depth in dB.
 */
export function placeNotch(notches, frequency, deepest = -30, depth = -15) {
  const near = notches.findIndex((f) => f !== null && Math.abs(f - frequency) / frequency < 0.03);
  if (near >= 0) return { index: near, gain: deepest };
  const free = notches.indexOf(null);
  return { index: free >= 0 ? free : 0, gain: depth };
}
