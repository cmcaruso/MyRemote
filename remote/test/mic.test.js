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
