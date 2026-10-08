import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DOTS, createDotGrid, falloff } from '../dotgrid.js';

/** Runs the grid for `ms` in 16 ms frames; returns whether it still moved on the last one. */
function run(grid, ms) {
  let busy = true;
  for (let t = 0; t < ms; t += 16) busy = grid.step(16);
  return busy;
}

const dotAt = (grid, x, y) => grid.dots.find((d) => d.x === x && d.y === y);

test('fills the surface with a centred grid', () => {
  const grid = createDotGrid();
  grid.layout(100, 50);
  // 4 × 2 dots 22 px apart, the 66 × 22 px block centred.
  assert.deepEqual(grid.dots.map((d) => [d.x, d.y]), [[17, 14], [39, 14], [61, 14], [83, 14], [17, 36], [39, 36], [61, 36], [83, 36]]);
  grid.layout(0, 0);
  assert.equal(grid.dots.length, 0);
});

test('falloff is full under the finger and gone at its reach', () => {
  assert.equal(falloff(0, 100), 1);
  assert.equal(falloff(50, 100), 0.5);
  assert.equal(falloff(100, 100), 0);
  assert.equal(falloff(150, 100), 0);
});

test('a finger pushes nearby dots away and lights them, and leaves far ones alone', () => {
  const grid = createDotGrid();
  grid.layout(440, 440);
  const near = dotAt(grid, 231, 231), far = dotAt(grid, 11, 11);
  grid.touches([{ x: 220, y: 231 }]);
  assert.equal(run(grid, 500), true);
  assert.ok(near.ox > 5, `pushed right, away from the finger: ${near.ox}`);
  assert.ok(Math.abs(near.oy) < 0.01);
  assert.ok(near.glow > 0.9);
  assert.deepEqual([far.ox, far.oy, far.glow], [0, 0, 0]);
});

test('after the finger lifts, the dots spring home and the grid comes to rest', () => {
  const grid = createDotGrid();
  grid.layout(440, 440);
  grid.touches([{ x: 220, y: 231 }]);
  run(grid, 300);
  grid.touches([]);
  assert.equal(grid.step(16), true, 'still moving just after the lift');
  assert.equal(run(grid, 4000), false);
  for (const d of grid.dots) assert.deepEqual([d.ox, d.oy, d.vx, d.vy, d.glow], [0, 0, 0, 0, 0]);
});

test('a finger held still keeps the grid busy', () => {
  const grid = createDotGrid();
  grid.layout(200, 200);
  grid.touches([{ x: 100, y: 100 }]);
  assert.equal(run(grid, 5000), true);
});

test('a tap sends out a ring that lights the dots at its front, then fades out', () => {
  const grid = createDotGrid();
  grid.layout(440, 440);
  grid.tap(11, 11);
  // After 200 ms the ring is about 180 px out: the dot at 176 px lights, one at 66 px doesn't.
  run(grid, 208);
  const front = dotAt(grid, 187, 11), behind = dotAt(grid, 77, 11);
  assert.ok(front.glow > 0.3, `front ${front.glow}`);
  assert.ok(behind.glow < 0.05, `behind ${behind.glow}`);
  assert.equal(run(grid, DOTS.ring.lifeMs + 3000), false);
});

test('a slow frame is simulated as a short one, so the springs stay calm', () => {
  const grid = createDotGrid();
  grid.layout(440, 440);
  grid.touches([{ x: 220, y: 231 }]);
  grid.step(1000);
  for (const d of grid.dots) assert.ok(Math.hypot(d.ox, d.oy) <= DOTS.push + DOTS.ring.push);
});
