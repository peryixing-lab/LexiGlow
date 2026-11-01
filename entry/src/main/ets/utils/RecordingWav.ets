/** Mono 44.1 kHz signed PCM16, bounded to a ten-second local recording. */
export const RECORDING_SAMPLE_RATE: number = 44100;
export const RECORDING_LIMIT_MS: number = 10000;
export const RECORDING_MAX_BYTES: number = RECORDING_SAMPLE_RATE * 2 * RECORDING_LIMIT_MS / 1000;

export function recordingWav(chunks: Uint8Array[], byteLength: number): ArrayBuffer {
  const size = Math.min(RECORDING_MAX_BYTES, Math.max(0, Math.floor(byteLength / 2) * 2));
  const bytes = new Uint8Array(44 + size);
  const view = new DataView(bytes.buffer);
  bytes.set([82, 73, 70, 70], 0); // RIFF
  view.setUint32(4, 36 + size, true);
  bytes.set([87, 65, 86, 69, 102, 109, 116, 32], 8); // WAVE / fmt
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, RECORDING_SAMPLE_RATE, true);
  view.setUint32(28, RECORDING_SAMPLE_RATE * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  bytes.set([100, 97, 116, 97], 36); // data
  view.setUint32(40, size, true);
  let offset = 44;
  chunks.forEach((chunk: Uint8Array) => {
    const count = Math.min(chunk.length, bytes.length - offset);
    if (count > 0) { bytes.set(chunk.subarray(0, count), offset); offset += count; }
  });
  return bytes.buffer;
}
