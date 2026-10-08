import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FLIP, createFlip, turnFor, unturn } from '../flip.js';

test('starts the right way up', () => {
  assert.equal(createFlip().flipped, false);
});

test('turns once held upside down for a moment', () => {
  const flip = createFlip();
  assert.equal(flip.update(-80, 0, 0), false);
  assert.equal(flip.update(-80, 0, FLIP.holdMs - 1), false);
  assert.equal(flip.update(-80, 0, FLIP.holdMs), true);
});

test('a brief tilt past the threshold does nothing', () => {
  const flip = createFlip();
  flip.update(-80, 0, 0);
  flip.update(10, 0, 200);
  assert.equal(flip.update(-80, 0, 450), false);
  assert.equal(flip.update(-80, 0, 450 + FLIP.holdMs), true);
});

test('stays upside down when laid flat, and turns back held upright', () => {
  const flip = createFlip();
  flip.update(-80, 0, 0);
  flip.update(-80, 0, 500);
  assert.equal(flip.update(0, 0, 1000), true);
  assert.equal(flip.update(0, 0, 3000), true);
  assert.equal(flip.update(70, 0, 3100), true);
  assert.equal(flip.update(70, 0, 3100 + FLIP.holdMs), false);
});

test('held on its side, in landscape, it never turns', () => {
  const flip = createFlip();
  // Upright landscape, then leaning forward past upright, where beta jumps to nearly -180.
  for (const [beta, gamma, t] of [[0, 85, 0], [0, 85, 1000], [-175, 80, 1100], [-175, 80, 2000], [-10, -88, 3000]]) {
    assert.equal(flip.update(beta, gamma, t), false);
  }
});

test('upside down, then onto its side, turns back', () => {
  const flip = createFlip();
  flip.update(-80, 0, 0);
  flip.update(-80, 0, FLIP.holdMs);
  flip.update(-5, 80, 1000);
  assert.equal(flip.update(-5, 80, 1000 + FLIP.holdMs), false);
});

test('upside down and leaning a little sideways still turns', () => {
  const flip = createFlip();
  flip.update(-70, 25, 0);
  assert.equal(flip.update(-70, 25, FLIP.holdMs), true);
});

test('nearly face down does nothing', () => {
  const flip = createFlip();
  flip.update(-165, 0, 0);
  assert.equal(flip.update(-165, 0, FLIP.holdMs), false);
});

test('ignores a missing reading', () => {
  const flip = createFlip();
  flip.update(-80, 0, 0);
  assert.equal(flip.update(null, null, 1000), false);
});

test('reset puts it the right way up', () => {
  const flip = createFlip();
  flip.update(-80, 0, 0);
  flip.update(-80, 0, FLIP.holdMs);
  flip.reset();
  assert.equal(flip.flipped, false);
  assert.equal(flip.update(-80, 0, FLIP.holdMs + 1), false);
});

test('turns a half round in portrait, a quarter in landscape', () => {
  assert.equal(turnFor(0), 180);
  assert.equal(turnFor(90), 90);
  assert.equal(turnFor(270), -90);
  assert.equal(turnFor(-90), -90);
  assert.equal(turnFor(180), 0);
});

test('a point maps back into the turned surface, corners to corners', () => {
  // A 100 × 50 surface: turned a quarter, its box on the page is 50 wide and 100 tall.
  const tall = { left: 10, top: 20, width: 50, height: 100 };
  // Turned clockwise its top-left corner sits at the box's top-right, its top-right at the bottom-right.
  assert.deepEqual(unturn(60, 20, tall, 90), { x: 0, y: 0 });
  assert.deepEqual(unturn(60, 120, tall, 90), { x: 100, y: 0 });
  assert.deepEqual(unturn(10, 20, tall, 90), { x: 0, y: 50 });
  // Anticlockwise its top-left is at the box's bottom-left.
  assert.deepEqual(unturn(10, 120, tall, -90), { x: 0, y: 0 });
  assert.deepEqual(unturn(10, 20, tall, -90), { x: 100, y: 0 });
  const wide = { left: 0, top: 0, width: 100, height: 50 };
  assert.deepEqual(unturn(100, 50, wide, 180), { x: 0, y: 0 });
  assert.deepEqual(unturn(30, 40, wide, 0), { x: 30, y: 40 });
});
