import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MIC, createMicEncoder, shouldDrop } from '../mic.js';

const samples = (frame) => Array.from({ length: frame.byteLength / 2 }, (_, i) => new DataView(frame).getInt16(i * 2, true));

test('halves 48 kHz to 24 kHz frames of 20 ms', () => {
  const encoder = createMicEncoder({ inRate: 48000 });
  assert.equal(encoder.rate, 24000);
  const frames = encoder.push(new Float32Array(960 * 2 + 10));
  assert.equal(frames.length, 2);
  assert.equal(frames[0].byteLength, 480 * 2);
});

test('averages each pair of input samples', () => {
  const encoder = createMicEncoder({ inRate: 4, outRate: 2, chunkMs: 1000 });
  const [frame] = encoder.push(new Float32Array([0.5, 0.5, -0.5, 0]));
  assert.deepEqual(samples(frame), [16383, -8192]);
});

test('keeps partial frames across blocks', () => {
  const encoder = createMicEncoder({ inRate: 48000 });
  let frames = 0;
  for (let i = 0; i < 15; i++) frames += encoder.push(new Float32Array(128)).length;
  assert.equal(frames, 2); // 15 × 128 = 1920 samples = 2 frames
});

test('clamps samples outside -1…1', () => {
  const encoder = createMicEncoder({ inRate: 2, outRate: 2, chunkMs: 1000 });
  const [frame] = encoder.push(new Float32Array([3, -3]));
  assert.deepEqual(samples(frame), [32767, -32768]);
});

test('at 44.1 kHz it sends 22.05 kHz', () => {
  const encoder = createMicEncoder({ inRate: 44100 });
  assert.equal(encoder.rate, 22050);
  assert.equal(encoder.push(new Float32Array(1764))[0].byteLength, 441 * 2);
});

test('passes a rate already at or under the target through', () => {
  assert.equal(createMicEncoder({ inRate: 16000 }).rate, 16000);
});

test('drops frames once the socket holds more than 100 ms', () => {
  assert.equal(MIC.maxQueuedMs, 100);
  assert.equal(shouldDrop(4800, 24000), false);
  assert.equal(shouldDrop(4801, 24000), true);
});

import { GUARD, HOWL, createGate, createHowlDetector, isPhoneMic, placeNotch } from '../mic.js';

test('tells the iPhone’s own mic from AirPods and headsets', () => {
  for (const label of ['iPhone Microphone', 'Microfono iPhone', 'iPad Microphone', '']) assert.equal(isPhoneMic(label), true, label);
  for (const label of ['AirPods Pro di Camillo', 'AirPods', 'Headset Microphone', 'Bose QC']) assert.equal(isPhoneMic(label), false, label);
});

const RATE = 48000;
const tone = (amplitude, n = 128) => Float32Array.from({ length: n }, (_, i) => amplitude * Math.sin(i / 5));
const peakOf = (block) => Math.max(...Array.from(block, Math.abs));
/** Runs `blocks` blocks of `amplitude` through the gate; returns the last output. */
const feed = (gate, amplitude, blocks) => {
  let out;
  for (let i = 0; i < blocks; i++) out = gate.process(tone(amplitude));
  return out;
};

test('the gate turns a steady room down', () => {
  const gate = createGate({ rate: RATE });
  const out = feed(gate, 0.01, 400); // about a second of room sound
  assert.equal(gate.open, false);
  assert.ok(peakOf(out) < 0.01 * 0.11, `${peakOf(out)}`);
});

test('a voice well over the room opens the gate at once', () => {
  const gate = createGate({ rate: RATE });
  feed(gate, 0.01, 400);
  const out = feed(gate, 0.3, 3); // 8 ms in
  assert.equal(gate.open, true);
  assert.ok(peakOf(out) > 0.29, `${peakOf(out)}`);
});

test('the gate holds through a short pause, then closes', () => {
  const gate = createGate({ rate: RATE });
  feed(gate, 0.01, 400);
  feed(gate, 0.3, 40);
  feed(gate, 0.01, Math.floor((GUARD.hold * RATE) / 128) - 5);
  assert.equal(gate.open, true);
  const out = feed(gate, 0.01, 60);
  assert.equal(gate.open, false);
  assert.ok(peakOf(out) < 0.01 * 0.11);
});

test('in a silent room, a whisper under -55 dBFS stays shut', () => {
  const gate = createGate({ rate: RATE });
  feed(gate, 0.00001, 200);
  feed(gate, 0.001, 20); // -63 dBFS RMS
  assert.equal(gate.open, false);
});

test('a louder room is learned, so it stops holding the gate open', () => {
  const gate = createGate({ rate: RATE });
  feed(gate, 0.001, 200);
  feed(gate, 0.01, 4 * 375 * 5); // the room got 20 dB louder for 20 s
  assert.equal(gate.open, false);
});

const BINS = 1024;
const hzPerBin = RATE / 2 / BINS;
/** A spectrum at -90 dB with speech-like bumps, plus a tone at `bin` of `level` dB. */
const spectrum = (bin, level) => {
  const s = new Float32Array(BINS).fill(-90);
  for (let i = 5; i < 200; i += 7) s[i] = -50;
  if (bin !== null) s[bin] = level;
  return s;
};

test('a steady tone far over the spectrum is feedback', () => {
  const detect = createHowlDetector({ rate: RATE, bins: BINS });
  let found = null;
  for (let t = 0; t <= HOWL.last + 0.05; t += 0.05) found = detect.update(spectrum(100, -20), t) ?? found;
  assert.equal(found, 100 * hzPerBin);
});

test('a tone that moves (a voice) is not', () => {
  const detect = createHowlDetector({ rate: RATE, bins: BINS });
  for (let i = 0, t = 0; i < 30; i++, t += 0.05) assert.equal(detect.update(spectrum(60 + (i % 3) * 4, -20), t), null);
});

test('a tone not far over the rest is not', () => {
  const detect = createHowlDetector({ rate: RATE, bins: BINS });
  const noisy = new Float32Array(BINS).fill(-50);
  noisy[100] = -50 + HOWL.peak - 5;
  for (let t = 0; t < 2; t += 0.05) assert.equal(detect.update(noisy, t), null);
});

test('it reports each ring once, then times it again', () => {
  const detect = createHowlDetector({ rate: RATE, bins: BINS });
  const found = [];
  for (let t = 0; t < 1; t += 0.05) {
    const f = detect.update(spectrum(100, -20), t);
    if (f) found.push(f);
  }
  assert.equal(found.length, 2);
});

test('notches: a free one first, deeper on the same tone, the oldest when full', () => {
  assert.deepEqual(placeNotch([null, null], 1000), { index: 0, gain: -15 });
  assert.deepEqual(placeNotch([1000, null], 1020), { index: 0, gain: -30 });
  assert.deepEqual(placeNotch([1000, null], 1500), { index: 1, gain: -15 });
  assert.deepEqual(placeNotch([1000, 1500], 2500), { index: 0, gain: -15 });
});
