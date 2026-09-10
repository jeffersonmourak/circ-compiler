// The share codec: a circ source in and out of a URL fragment.
//
// Two keys, not a version byte. `#src=` carries deflate-raw plus base64url;
// `#src0=` carries plain base64url, for a browser with no `CompressionStream`.
// A reader who pastes either one gets their circuit back.
//
// The codec is injected rather than reached for, so a test can exercise both
// paths: `CompressionStream` is undefined under bun, and a test supplies a
// `node:zlib` codec instead. Nothing here throws — every failure is a value,
// because a malformed fragment is a thing a stranger can hand you, not a bug.
//
// No DOM, no `location`, no storage.

/** Characters of payload. Past this the Share button offers the raw source. */
export const SHARE_CAP = 8192;

export type ShareKey = 'src' | 'src0';

export interface DeflateCodec {
  deflateRaw(bytes: Uint8Array<ArrayBufferLike>): Promise<Uint8Array>;
  inflateRaw(bytes: Uint8Array<ArrayBufferLike>): Promise<Uint8Array>;
}

async function throughStream(
  bytes: Uint8Array<ArrayBufferLike>,
  stream: ReadableWritablePair<Uint8Array, Uint8Array>,
): Promise<Uint8Array> {
  const source = new Blob([bytes as BlobPart]).stream() as unknown as ReadableStream<Uint8Array>;
  const piped = source.pipeThrough(stream);
  const buffer = await new Response(piped as unknown as BodyInit).arrayBuffer();
  return new Uint8Array(buffer);
}

/** A codec over `CompressionStream('deflate-raw')`, or null where the global is
 *  absent or the format is unsupported (older Safari and Firefox, and bun). */
export function webStreamsCodec(): DeflateCodec | null {
  const CS = (globalThis as { CompressionStream?: new (f: string) => ReadableWritablePair<Uint8Array, Uint8Array> })
    .CompressionStream;
  const DS = (globalThis as { DecompressionStream?: new (f: string) => ReadableWritablePair<Uint8Array, Uint8Array> })
    .DecompressionStream;
  if (!CS || !DS) return null;
  try {
    // Constructing is the only way to know the format is supported.
    void new CS('deflate-raw');
  } catch {
    return null;
  }
  return {
    deflateRaw: (bytes) => throughStream(bytes, new CS('deflate-raw')),
    inflateRaw: (bytes) => throughStream(bytes, new DS('deflate-raw')),
  };
}

const B64_URL = /^[A-Za-z0-9_-]*$/;

/** URL-safe base64 with no padding. Chunked, because spreading a large array
 *  into `String.fromCharCode` overflows the argument limit. */
export function toBase64Url(bytes: Uint8Array): string {
  let binary = '';
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** Null on anything outside the URL-safe alphabet, or on a length that cannot
 *  be a base64 body. Never throws. */
export function fromBase64Url(s: string): Uint8Array | null {
  if (!B64_URL.test(s)) return null;
  const padded = s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4);
  try {
    const binary = atob(padded);
    const out = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) out[i] = binary.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

export type EncodeResult =
  | { ok: true; key: ShareKey; payload: string; fragment: string; chars: number }
  | { ok: false; reason: 'too-large'; key: ShareKey; chars: number; cap: number };

export type DecodeReason = 'no-key' | 'unknown-key' | 'bad-base64' | 'bad-deflate' | 'bad-utf8' | 'no-codec';

export type DecodeResult =
  | { ok: true; key: ShareKey; source: string }
  | { ok: false; reason: DecodeReason };

export async function encodeShare(
  source: string,
  codec?: DeflateCodec | null,
  cap: number = SHARE_CAP,
): Promise<EncodeResult> {
  const utf8 = new TextEncoder().encode(source);
  let key: ShareKey = 'src0';
  // Widened on purpose: a codec may hand back a view over any buffer kind, and
  // the encoder's own output is narrower than that.
  let bytes: Uint8Array<ArrayBufferLike> = utf8;
  if (codec) {
    try {
      bytes = await codec.deflateRaw(utf8);
      key = 'src';
    } catch {
      // A codec that fails at runtime is the same as not having one.
      bytes = utf8;
      key = 'src0';
    }
  }
  const payload = toBase64Url(bytes);
  const chars = payload.length;
  if (chars > cap) return { ok: false, reason: 'too-large', key, chars, cap };
  return { ok: true, key, payload, fragment: `#${key}=${payload}`, chars };
}

/**
 * Every key the fragment carries — `#src=` beats `#src0=` inside `src`, and a
 * `#pick=` alongside either is kept rather than discarded.
 *
 * That is deliberate: a failed decode must be able to fall through to the pick
 * in the same fragment, which a three-way union could not express because it
 * would have thrown the lower-precedence key away before the decode was even
 * attempted. The precedence lives in `resolveInitial`, not here.
 */
export interface HashIntent {
  src?: { key: ShareKey; payload: string };
  pick?: string;
  /** Present but unrecognised; still owed a fall-through note. */
  unknown?: readonly string[];
}

export function readHash(hash: string): HashIntent {
  const body = hash.startsWith('#') ? hash.slice(1) : hash;
  if (body === '') return {};
  const intent: HashIntent = {};
  const unknown: string[] = [];
  let src0: string | null = null;

  for (const part of body.split('&')) {
    if (part === '') continue;
    const eq = part.indexOf('=');
    const name = eq === -1 ? part : part.slice(0, eq);
    const value = eq === -1 ? '' : part.slice(eq + 1);
    if (name === 'src') intent.src = { key: 'src', payload: value };
    else if (name === 'src0') src0 = value;
    else if (name === 'pick') intent.pick = decodeURIComponent(value);
    else unknown.push(name);
  }
  // `#src=` wins; `#src0=` only fills in when it is absent.
  if (!intent.src && src0 !== null) intent.src = { key: 'src0', payload: src0 };
  if (unknown.length > 0) intent.unknown = unknown;
  return intent;
}

export async function decodeShare(hash: string, codec?: DeflateCodec | null): Promise<DecodeResult> {
  const intent = readHash(hash);
  if (!intent.src) {
    // A fragment carrying something, just not a share key.
    if (intent.unknown && intent.unknown.length > 0) return { ok: false, reason: 'unknown-key' };
    return { ok: false, reason: 'no-key' };
  }
  const { key, payload } = intent.src;
  const bytes = fromBase64Url(payload);
  if (!bytes) return { ok: false, reason: 'bad-base64' };

  let utf8 = bytes;
  if (key === 'src') {
    if (!codec) return { ok: false, reason: 'no-codec' };
    try {
      utf8 = await codec.inflateRaw(bytes);
    } catch {
      return { ok: false, reason: 'bad-deflate' };
    }
  }
  try {
    // `fatal` is what turns invalid UTF-8 into a value instead of U+FFFD soup.
    return { ok: true, key, source: new TextDecoder('utf-8', { fatal: true }).decode(utf8) };
  } catch {
    return { ok: false, reason: 'bad-utf8' };
  }
}

/** `href` with its fragment replaced; path and query are preserved. */
export function shareUrl(href: string, fragment: string): string {
  try {
    const u = new URL(href);
    u.hash = fragment;
    return u.toString();
  } catch {
    return href;
  }
}
