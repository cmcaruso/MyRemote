/**
 * The trackpad's dot grid: a field of dots that the fingers push aside, lighting up as they go, and that
 * springs back once they lift. A tap (a click) sends a ring out through it.
 *
 * Pure and timer-free: `layout` sets the surface's size, `touches` the fingers down now and `tap` a click,
 * all in the surface's own pixels; `step` moves every dot on by a frame's time and returns whether anything
 * still moves, so the caller draws only while it does. Drawing is the caller's.
 */

/** The look picked on the phone, as Repel in the UI polish prototype. */
export const DOTS = Object.freeze({
  spacing: 22, // px between dots
  size: 2, // dot radius, px
  reach: 110, // px around a finger that it moves dots within
  push: 16, // px a dot right by a finger is pushed away
  decayMs: 350, // a lit dot fades with this time constant
  omega: 9, // spring back: natural frequency, rad/s
  zeta: 0.55, // and damping ratio: a slight bounce
  idle: 0.22, // an idle dot's opacity
  ring: Object.freeze({ speed: 0.9, lifeMs: 700, width: 16, push: 6 }), // a tap's ring: px/ms, ms, px, px
});

/** How much a finger at `distance` moves a dot: 1 under it, easing to 0 at `reach`. */
export function falloff(distance, reach) {
  const t = 1 - distance / reach;
  return t <= 0 ? 0 : t >= 1 ? 1 : t * t * (3 - 2 * t);
}

/** Longest frame a step simulates, ms: a slow frame mustn't throw the springs. */
const MAX_STEP = 34;
/** Below this, a dot counts as still. */
const REST = 0.01;

export function createDotGrid(o = DOTS) {
  /** @type {{ x: number, y: number, ox: number, oy: number, vx: number, vy: number, lit: number, glow: number }[]} */
  let dots = [];
  let fingers = []; // { x, y }
  let rings = []; // { x, y, age }

  return {
    /** Each dot's home (`x`, `y`), offset from it (`ox`, `oy`) and brightness, 0 to 1 (`glow`). */
    get dots() {
      return dots;
    },
    /** Fills a `width` × `height` surface with dots, centred, and lets them rest. */
    layout(width, height) {
      const cols = Math.max(0, Math.floor(width / o.spacing));
      const rows = Math.max(0, Math.floor(height / o.spacing));
      const x0 = (width - (cols - 1) * o.spacing) / 2;
      const y0 = (height - (rows - 1) * o.spacing) / 2;
      dots = [];
      for (let j = 0; j < rows; j++) {
        for (let i = 0; i < cols; i++) {
          dots.push({ x: x0 + i * o.spacing, y: y0 + j * o.spacing, ox: 0, oy: 0, vx: 0, vy: 0, lit: 0, glow: 0 });
        }
      }
    },
    /** @param {{ x: number, y: number }[]} list the fingers down now */
    touches(list) {
      fingers = list.map(({ x, y }) => ({ x, y }));
    },
    tap(x, y) {
      rings.push({ x, y, age: 0 });
    },
    /** Moves everything on by `ms`; returns whether anything still moves. */
    step(ms) {
      const dt = Math.min(ms, MAX_STEP);
      const s = dt / 1000;
      const fade = Math.exp(-dt / o.decayMs);
      for (const r of rings) r.age += dt;
      rings = rings.filter((r) => r.age < o.ring.lifeMs);
      let busy = fingers.length > 0 || rings.length > 0;
      for (const d of dots) {
        let near = 0, wave = 0, tx = 0, ty = 0;
        for (const f of fingers) {
          const dx = d.x - f.x, dy = d.y - f.y, dist = Math.hypot(dx, dy);
          const k = falloff(dist, o.reach);
          if (k === 0) continue;
          near = Math.max(near, k);
          if (dist > 0) { tx += (dx / dist) * k * o.push; ty += (dy / dist) * k * o.push; }
        }
        for (const r of rings) {
          const dx = d.x - r.x, dy = d.y - r.y, dist = Math.hypot(dx, dy);
          const k = Math.exp(-(((dist - r.age * o.ring.speed) / o.ring.width) ** 2)) * (1 - r.age / o.ring.lifeMs);
          if (k < REST) continue;
          wave = Math.max(wave, k);
          if (dist > 0) { tx += (dx / dist) * k * o.ring.push; ty += (dy / dist) * k * o.ring.push; }
        }
        d.lit = Math.max(near, d.lit * fade);
        if (d.lit < REST) d.lit = 0;
        d.glow = Math.max(d.lit, wave);
        // A damped spring pulls each dot toward where the fingers and rings push it, or home.
        d.vx += (o.omega ** 2 * (tx - d.ox) - 2 * o.zeta * o.omega * d.vx) * s;
        d.vy += (o.omega ** 2 * (ty - d.oy) - 2 * o.zeta * o.omega * d.vy) * s;
        d.ox += d.vx * s;
        d.oy += d.vy * s;
        const moving = Math.abs(d.ox) + Math.abs(d.oy) + Math.abs(d.vx) + Math.abs(d.vy) > REST * 5;
        if (!moving && tx === 0 && ty === 0) d.ox = d.oy = d.vx = d.vy = 0;
        if (moving || d.glow > 0) busy = true;
      }
      return busy;
    },
  };
}
