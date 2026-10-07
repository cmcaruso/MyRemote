const OPEN = 1;

/**
 * Sends pointer motion to the Host as relative deltas.
 *
 * Motion goes out straight from touchmove while the socket keeps up. While it is backed up
 * (bufferedAmount > 0) deltas are summed and sent as one frame by `drain()`, which the
 * Remote calls once per animation frame.
 *
 * @param {{ readyState: number, bufferedAmount: number, send(text: string): void }} socket
 */
export function createMotionSender(socket) {
  let dx = 0;
  let dy = 0;

  function flush() {
    if ((dx === 0 && dy === 0) || socket.bufferedAmount > 0) return;
    socket.send(JSON.stringify({ t: 'm', dx, dy }));
    dx = 0;
    dy = 0;
  }

  return {
    /** Adds a finger delta (already accelerated) in Host pixels. */
    add(ddx, ddy) {
      if (socket.readyState !== OPEN) return;
      dx += ddx;
      dy += ddy;
      flush();
    },
    /** Sends whatever backpressure held back. */
    drain() {
      flush();
    },
  };
}
