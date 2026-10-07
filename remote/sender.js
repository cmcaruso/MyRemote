const OPEN = 1;

/**
 * Sends commands to the Host.
 *
 * Motion and scroll go out straight from touchmove while the socket keeps up. While it is backed up
 * (bufferedAmount > 0) their deltas are summed and sent as one frame each by `drain()`, which the
 * Remote calls once per animation frame. Discrete commands (clicks, button down/up, scroll end) go out
 * at once, after any pending motion and scroll, so they land in order.
 *
 * @param {{ readyState: number, bufferedAmount: number, send(text: string): void }} socket
 */
export function createSender(socket) {
  const pending = {
    m: { dx: 0, dy: 0 },
    s: { dx: 0, dy: 0 },
  };

  function flush({ force = false } = {}) {
    if (!force && socket.bufferedAmount > 0) return;
    for (const [t, d] of Object.entries(pending)) {
      if (d.dx === 0 && d.dy === 0) continue;
      socket.send(JSON.stringify({ t, dx: d.dx, dy: d.dy }));
      d.dx = 0;
      d.dy = 0;
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
