import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createSender } from '../sender.js';

/** Stands in for a browser WebSocket: records frames, lets a test fake backpressure. */
function fakeSocket({ readyState = 1, bufferedAmount = 0 } = {}) {
  return { readyState, bufferedAmount, frames: [], send(text) { this.frames.push(JSON.parse(text)); } };
}

test('sends a move frame straight away when the socket is idle', () => {
  const socket = fakeSocket();
  const sender = createSender(socket);

  sender.move(1.5, -2);

  assert.deepEqual(socket.frames, [{ t: 'm', dx: 1.5, dy: -2 }]);
});

test('coalesces motion while the socket is backed up and sends the total on drain', () => {
  const socket = fakeSocket({ bufferedAmount: 120 });
  const sender = createSender(socket);

  sender.move(1.5, -2);
  sender.move(2.25, 1);
  sender.move(-0.5, 0.5);
  assert.deepEqual(socket.frames, []);

  socket.bufferedAmount = 0;
  sender.drain();

  assert.deepEqual(socket.frames, [{ t: 'm', dx: 3.25, dy: -0.5 }]);
});

test('sends nothing when there is no motion', () => {
  const socket = fakeSocket();
  const sender = createSender(socket);

  sender.drain();
  sender.move(0, 0);

  assert.deepEqual(socket.frames, []);
});

test('drops motion made while disconnected so the pointer does not jump on reconnect', () => {
  const socket = fakeSocket({ readyState: 0 });
  const sender = createSender(socket);

  sender.move(40, 40);
  socket.readyState = 1;
  sender.drain();
  sender.move(1, 2);

  assert.deepEqual(socket.frames, [{ t: 'm', dx: 1, dy: 2 }]);
});

test('coalesces scroll like motion while the socket is backed up', () => {
  const socket = fakeSocket({ bufferedAmount: 64 });
  const sender = createSender(socket);

  sender.scroll(0, -4);
  sender.scroll(0, -6.5);
  socket.bufferedAmount = 0;
  sender.drain();

  assert.deepEqual(socket.frames, [{ t: 's', dx: 0, dy: -10.5 }]);
});

test('a discrete command goes out at once, after the motion and scroll before it', () => {
  const socket = fakeSocket({ bufferedAmount: 64 });
  const sender = createSender(socket);

  sender.move(3, 4);
  sender.scroll(0, -2);
  sender.send({ t: 'c', b: 0, n: 1 });

  assert.deepEqual(socket.frames, [
    { t: 'm', dx: 3, dy: 4 },
    { t: 's', dx: 0, dy: -2 },
    { t: 'c', b: 0, n: 1 },
  ]);
});

test('drops discrete commands while disconnected', () => {
  const socket = fakeSocket({ readyState: 3 });
  const sender = createSender(socket);

  sender.send({ t: 'c', b: 0, n: 1 });

  assert.deepEqual(socket.frames, []);
});
