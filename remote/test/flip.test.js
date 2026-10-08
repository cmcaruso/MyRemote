import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FLIP, createFlip } from '../flip.js';

test('starts the right way up', () => {
  assert.equal(createFlip().flipped, false);
});

test('turns once held upside down for a moment', () => {
  const flip = createFlip();
  assert.equal(flip.update(-80, 0), false);
  assert.equal(flip.update(-80, FLIP.holdMs - 1), false);
  assert.equal(flip.update(-80, FLIP.holdMs), true);
});

test('a brief tilt past the threshold does nothing', () => {
  const flip = createFlip();
  flip.update(-80, 0);
  flip.update(10, 200);
  assert.equal(flip.update(-80, 450), false);
  assert.equal(flip.update(-80, 450 + FLIP.holdMs), true);
});

test('stays upside down when laid flat, and turns back held upright', () => {
  const flip = createFlip();
  flip.update(-80, 0);
  flip.update(-80, 500);
  assert.equal(flip.update(0, 1000), true);
  assert.equal(flip.update(0, 3000), true);
  assert.equal(flip.update(70, 3100), true);
  assert.equal(flip.update(70, 3100 + FLIP.holdMs), false);
});

test('ignores a missing reading', () => {
  const flip = createFlip();
  flip.update(-80, 0);
  assert.equal(flip.update(null, 1000), false);
});
