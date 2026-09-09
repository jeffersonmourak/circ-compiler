// A compiled artifact's identity.
//
// FNV-1a over the bytes, used to decide whether a canvas needs rebuilding.
// Every consumer must hash the same way, or a rebuild happens on every
// keystroke and the reader's toggled pins are lost each time.
//
// Lifted out of the playground island so the docs' live editors share it
// rather than growing a second, subtly different copy.

/** FNV-1a, 32-bit, as an unsigned integer. */
export function fnv1a(bytes: Uint8Array): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < bytes.length; i += 1) {
    h ^= bytes[i];
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}
