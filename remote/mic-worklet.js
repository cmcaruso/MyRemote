// Runs on the audio thread: hands each block of the microphone's samples to the page.
class MicTap extends AudioWorkletProcessor {
  process(inputs) {
    const channel = inputs[0]?.[0];
    if (channel) this.port.postMessage(channel.slice());
    return true;
  }
}
registerProcessor('mic-tap', MicTap);
