import { DEFAULTS, pointerGain } from './trackpad.js';

/**
 * The Laser's "air pointer": turns the phone's rotation into deltas for the dot on the Mac.
 *
 * Relative, like a Logitech Spotlight: turning left or right (yaw, about the vertical) moves the dot
 * sideways, tilting the top up or down (pitch, about the screen's horizontal axis) moves it up and
 * down. Yaw is measured about gravity, so it works whether the phone is held flat or upright.
 * Pure: every call gets one motion sample and returns `{ dx, dy }` in Host points.
 */

export const LASER = Object.freeze({
  gain: 45, // points per degree turned
  deadzone: 1.5, // deg/s of rotation ignored, so a hand held still keeps the dot still
  steady: 8, // deg/s: slower rotation is damped (half gain here), so walking and swaying don't drift the dot
  linger: 1500, // ms the dot stays after the thumb lifts when steering by drag, to swipe again from there
});

/**
 * The rotation rate as a vector about the device's x (right), y (top) and z (out of the screen) axes,
 * in deg/s. WebKit fills `alpha`, `beta`, `gamma` with the rates about x, y, z (Core Motion's order),
 * not the spec's z, x, y.
 */
export const rotationVector = (rate) => [rate.alpha ?? 0, rate.beta ?? 0, rate.gamma ?? 0];

const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const dead = (r, zone) => (Math.abs(r) <= zone ? 0 : r - Math.sign(r) * zone);
/** Fades out slow rotation: full gain for deliberate pointing, little for the slow turns of walking. */
const steady = (r, k) => (k > 0 ? (r * r * r) / (r * r + k * k) : r);

/**
 * @param {number[]} rotation deg/s about the device's x, y, z (see `rotationVector`)
 * @param {{ x: number, y: number, z: number }} gravity `accelerationIncludingGravity`, m/s²
 * @param {number} angle the screen's orientation angle: 0 portrait, 90 turned left, -90 or 270 turned right
 * @param {number} dt seconds since the last sample
 */
export function airDelta(rotation, gravity, angle, dt, p = LASER) {
  const a = (angle * Math.PI) / 180;
  // The screen's right and up, in device axes.
  const right = [Math.cos(a), -Math.sin(a), 0];
  const screenUp = [Math.sin(a), Math.cos(a), 0];

  // Up is along gravity; take the sign that points out of the screen and toward its top, whichever
  // way the platform signs gravity, since the phone is held facing up or facing the user.
  const g = [gravity.x ?? 0, gravity.y ?? 0, gravity.z ?? 0];
  const length = Math.hypot(...g);
  let up = length > 0 ? g.map((c) => c / length) : [0, 0, 1];
  if (dot(up, [screenUp[0], screenUp[1], 1]) < 0) up = up.map((c) => -c);

  // Right-hand rule: turning right is negative rotation about up; tilting the top up is positive
  // rotation about the screen's right. Screen y grows downward.
  const yaw = steady(dead(dot(rotation, up), p.deadzone), p.steady);
  const pitch = steady(dead(dot(rotation, right), p.deadzone), p.steady);
  return { dx: -yaw * p.gain * dt, dy: -pitch * p.gain * dt };
}

/**
 * Steering by drag instead: a thumb movement of `dx`, `dy` px over `dtMs`, through the trackpad's own
 * speed and acceleration curve (and the user's trackpad settings), so it feels like the trackpad.
 */
export function dragDelta(dx, dy, dtMs, params = {}) {
  const g = pointerGain({ ...DEFAULTS, ...params }, Math.hypot(dx, dy) / Math.max(dtMs, 4));
  return { dx: dx * g, dy: dy * g };
}
