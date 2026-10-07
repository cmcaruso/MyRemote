import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createMotionSender } from '../motion-sender.js';

/** Stands in for a browser WebSocket: records frames, lets a test fake backpressure. */
function fakeSocket({ readyState = 1, bufferedAmount = 0 } = {}) {
  return { readyState, bufferedAmount, frames: [], send(text) { this.frames.push(JSON.parse(text)); } };
}

test('sends a move frame straight away when the socket is idle', () => {
  const socket = fakeSocket();
  const motion = createMotionSender(socket);

  motion.add(1.5, -2);

  assert.deepEqual(socket.frames, [{ t: 'm', dx: 1.5, dy: -2 }]);
});

test('coalesces motion while the socket is backed up and sends the total on drain', () => {
  const socket = fakeSocket({ bufferedAmount: 120 });
  const motion = createMotionSender(socket);

  motion.add(1.5, -2);
  motion.add(2.25, 1);
  motion.add(-0.5, 0.5);
  assert.deepEqual(socket.frames, []);

  socket.bufferedAmount = 0;
  motion.drain();

  assert.deepEqual(socket.frames, [{ t: 'm', dx: 3.25, dy: -0.5 }]);
});

test('sends nothing when there is no motion', () => {
  const socket = fakeSocket();
  const motion = createMotionSender(socket);

  motion.drain();
  motion.add(0, 0);

  assert.deepEqual(socket.frames, []);
});

test('drops motion made while disconnected so the pointer does not jump on reconnect', () => {
  const socket = fakeSocket({ readyState: 0 });
  const motion = createMotionSender(socket);

  motion.add(40, 40);
  socket.readyState = 1;
  motion.drain();
  motion.add(1, 2);

  assert.deepEqual(socket.frames, [{ t: 'm', dx: 1, dy: 2 }]);
});
