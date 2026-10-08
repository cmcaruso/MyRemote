import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LASER, airDelta, rotationVector } from '../laser.js';

const near = (actual, expected) => {
  assert.ok(Math.abs(actual.dx - expected.dx) < 1e-9 && Math.abs(actual.dy - expected.dy) < 1e-9,
    `${JSON.stringify(actual)} ≠ ${JSON.stringify(expected)}`);
};
const p = { ...LASER, deadzone: 0 };
// Face up on a table, and upright facing the user; gravity signed either way.
const FLAT = { x: 0, y: 0, z: -9.81 };
const UPRIGHT = { x: 0, y: -9.81, z: 0 };

test('reads WebKit’s rotation rate as x, y, z', () => {
  assert.deepEqual(rotationVector({ alpha: 1, beta: 2, gamma: 3 }), [1, 2, 3]);
  assert.deepEqual(rotationVector({}), [0, 0, 0]);
});

test('flat in portrait: turning right moves the dot right', () => {
  // Turning right, seen from above, is clockwise: negative about z.
  near(airDelta([0, 0, -10], FLAT, 0, 0.1, p), { dx: 10 * p.gain * 0.1, dy: 0 });
});

test('flat in portrait: tilting the top up moves the dot up', () => {
  near(airDelta([10, 0, 0], FLAT, 0, 0.1, p), { dx: 0, dy: -10 * p.gain * 0.1 });
});

test('upright in portrait: yaw is about the phone’s top axis now', () => {
  // Held facing the user, turning right is negative about y (up).
  near(airDelta([0, -10, 0], UPRIGHT, 0, 0.1, p), { dx: 10 * p.gain * 0.1, dy: 0 });
  near(airDelta([10, 0, 0], UPRIGHT, 0, 0.1, p), { dx: 0, dy: -10 * p.gain * 0.1 });
});

test('the sign of gravity doesn’t matter', () => {
  const flipped = { x: 0, y: 0, z: 9.81 };
  near(airDelta([0, 0, -10], flipped, 0, 0.1, p), airDelta([0, 0, -10], FLAT, 0, 0.1, p));
});

test('in landscape, tilting up is about the phone’s long axis', () => {
  // Turned left (90): the phone's top points left, so the screen's right is the device's −y.
  near(airDelta([0, -10, 0], FLAT, 90, 0.1, p), { dx: 0, dy: -10 * p.gain * 0.1 });
  // Turned right (−90 or 270): the screen's right is the device's +y.
  near(airDelta([0, 10, 0], FLAT, -90, 0.1, p), { dx: 0, dy: -10 * p.gain * 0.1 });
  near(airDelta([0, 10, 0], FLAT, 270, 0.1, p), { dx: 0, dy: -10 * p.gain * 0.1 });
  // Yaw stays about the vertical.
  near(airDelta([0, 0, -10], FLAT, 90, 0.1, p), { dx: 10 * p.gain * 0.1, dy: 0 });
});

test('a hand held still doesn’t move the dot', () => {
  near(airDelta([1, -1.2, 0.8], FLAT, 0, 0.016), { dx: 0, dy: 0 });
});

test('the deadzone is taken off, so motion starts smoothly past it', () => {
  near(airDelta([0, 0, -11.5], FLAT, 0, 1), { dx: 10 * LASER.gain, dy: 0 });
});

test('scales with the time between samples', () => {
  const one = airDelta([0, 0, -20], FLAT, 0, 1 / 60, p);
  const two = airDelta([0, 0, -20], FLAT, 0, 2 / 60, p);
  assert.ok(Math.abs(two.dx - 2 * one.dx) < 1e-9);
});
