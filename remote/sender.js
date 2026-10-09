const OPEN = 1;

/**
 * Sends commands to the Host.
 *
 * Motion, scroll, Laser motion and Gesture deltas go out straight from touchmove while the socket keeps up. While it is backed up
 * (bufferedAmount > 0) their deltas are summed (and only the newest volume level kept) and sent as
 * one frame each by `drain()`, which the
 * Remote calls once per animation frame. Discrete commands (clicks, button down/up, scroll end) go out
 * at once, after any pending motion and scroll, so they land in order.
 *
 * @param {{ readyState: number, bufferedAmount: number, send(text: string): void }} socket
 */
export function createSender(socket) {
  const pending = {
    m: { dx: 0, dy: 0 },
    s: { dx: 0, dy: 0 },
    l: { dx: 0, dy: 0 },
  };
  /** Gesture deltas not sent yet, by Gesture name. */
  const gestures = new Map();
  let volume = null; // newest level not sent yet

  function flush({ force = false } = {}) {
    if (!force && socket.bufferedAmount > 0) return;
    for (const [t, d] of Object.entries(pending)) {
      if (d.dx === 0 && d.dy === 0) continue;
      socket.send(JSON.stringify({ t, dx: d.dx, dy: d.dy }));
      d.dx = 0;
      d.dy = 0;
    }
    for (const [g, d] of gestures) socket.send(JSON.stringify({ t: 'g', g, d }));
    gestures.clear();
    if (volume !== null) {
      socket.send(JSON.stringify({ t: 'v', v: volume }));
      volume = null;
    }
  }

  function add(t, dx, dy) {
    if (socket.readyState !== OPEN) return;
    pending[t].dx += dx;
    pending[t].dy += dy;
    flush();
  }

  return {
    /** Adds a pointer delta (already accelerated) in Host pixels. */
    move(dx, dy) {
      add('m', dx, dy);
    },
    /** Adds a scroll delta in Host pixels. */
    scroll(dx, dy) {
      add('s', dx, dy);
    },
    /** Adds a Laser delta in Host points. */
    laser(dx, dy) {
      add('l', dx, dy);
    },
    /** Adds to a Gesture's delta, in its own units (magnification for pinch, degrees for rotate). */
    gesture(g, d) {
      if (socket.readyState !== OPEN) return;
      gestures.set(g, (gestures.get(g) ?? 0) + d);
      flush();
    },
    /** Sets the Mac's output volume, 0 to 1; under backpressure only the newest level goes out. */
    volume(v) {
      if (socket.readyState !== OPEN) return;
      volume = v;
      flush();
    },
    /** Sends a discrete command such as `{ t: 'c', b: 0, n: 1 }`. */
    send(command) {
      if (socket.readyState !== OPEN) return;
      flush({ force: true });
      socket.send(JSON.stringify(command));
    },
    /** Sends whatever backpressure held back. */
    drain() {
      flush();
    },
  };
}
