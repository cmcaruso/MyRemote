import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createVolumeSlider } from '../volume-slider.js';

const host = (v, { muted = false, settable = true } = {}) => ({ t: 'vol', v, muted, settable });

test('shows what the Host reports', () => {
  const slider = createVolumeSlider();
  slider.host(host(0.4, { muted: true }), 0);
  assert.deepEqual(slider.state, { level: 0.4, muted: true, settable: true });
});

test('dragging returns the level to send, clamped to 0 through 1', () => {
  const slider = createVolumeSlider();
  assert.equal(slider.touch(0.25, 0), 0.25);
  assert.equal(slider.touch(1.3, 16), 1);
  assert.equal(slider.touch(-0.1, 32), 0);
});

test('ignores the Host while the finger is on the slider', () => {
  const slider = createVolumeSlider();
  slider.host(host(0.4), 0);
  slider.touch(0.6, 10);
  slider.host(host(0.45), 20); // an echo from earlier in the drag
  assert.equal(slider.state.level, 0.6);
});

test('after release, ignores late echoes until the Host confirms the level it was set to', () => {
  const slider = createVolumeSlider();
  slider.touch(0.2, 0);
  slider.touch(0.5, 16);
  slider.release(20);
  slider.host(host(0.2), 60); // stale echo
  assert.equal(slider.state.level, 0.5);
  slider.host(host(0.5, { muted: false }), 80); // the Host caught up
  slider.host(host(0.3), 500); // a change made on the Mac
  assert.equal(slider.state.level, 0.3);
});

test('after release, follows the Host again within a second even if it never confirms', () => {
  const slider = createVolumeSlider();
  slider.touch(0.5, 0);
  slider.release(10);
  slider.host(host(0.44), 300);
  assert.equal(slider.state.level, 0.5);
  slider.host(host(0.44), 1100);
  assert.equal(slider.state.level, 0.44);
});

test('mute and whether the slider works always come from the Host', () => {
  const slider = createVolumeSlider();
  slider.touch(0.5, 0);
  slider.host(host(0.1, { muted: true, settable: false }), 10);
  assert.deepEqual(slider.state, { level: 0.5, muted: true, settable: false });
});
