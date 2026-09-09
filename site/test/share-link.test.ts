// A share link is the one artefact of this playground a stranger can hand you,
// so every malformed shape is a value rather than a throw, and every shipped
// source is proved to survive the round trip byte for byte.
//
// `CompressionStream` is undefined under bun, so the deflate path is driven
// with a `node:zlib` codec of the same format.
import { describe, expect, test } from 'bun:test';
import { deflateRawSync, inflateRawSync } from 'node:zlib';
import {
  SHARE_CAP,
  decodeShare,
  encodeShare,
  fromBase64Url,
  readHash,
  shareUrl,
  toBase64Url,
  webStreamsCodec,
  type DeflateCodec,
} from '../src/utils/share-link.ts';
import { examples } from '../src/content/examples.ts';
import { tour } from '../src/content/tour.ts';

const zlibCodec: DeflateCodec = {
  deflateRaw: async (bytes) => new Uint8Array(deflateRawSync(bytes)),
  inflateRaw: async (bytes) => new Uint8Array(inflateRawSync(bytes)),
};

const sources = [...examples.map((e) => e.source), ...tour.map((t) => t.source)];

/** A seeded generator, so the incompressible payload is the same every run. */
function incompressible(length: number): string {
  let seed = 20260909;
  let out = '';
  for (let i = 0; i < length; i += 1) {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    out += String.fromCharCode(33 + (seed % 90));
  }
  return out;
}

describe('base64url', () => {
  test('round-trips arbitrary bytes with no padding', () => {
    for (const size of [0, 1, 2, 3, 255, 40000]) {
      const bytes = new Uint8Array(size);
      for (let i = 0; i < size; i += 1) bytes[i] = (i * 7 + 13) % 256;
      const encoded = toBase64Url(bytes);
      expect(encoded).toMatch(/^[A-Za-z0-9_-]*$/);
      expect(encoded).not.toContain('=');
      expect(Array.from(fromBase64Url(encoded)!)).toEqual(Array.from(bytes));
    }
  });

  test('returns null, never throws, on a bad alphabet', () => {
    for (const bad of ['!!', 'a b', '====', 'a+b', 'a/b', 'é']) {
      expect(fromBase64Url(bad)).toBeNull();
    }
  });
});

describe('encodeShare', () => {
  test('picks #src= when a codec is present', async () => {
    const r = await encodeShare('input a\n', zlibCodec);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.key).toBe('src');
    expect(r.fragment.startsWith('#src=')).toBe(true);
    expect(r.chars).toBe(r.payload.length);
  });

  test('falls back to #src0= with a null codec', async () => {
    const source = 'input a\n';
    const r = await encodeShare(source, null);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.key).toBe('src0');
    expect(r.fragment.startsWith('#src0=')).toBe(true);
    // Plain base64url of the UTF-8 bytes, nothing more.
    expect(r.payload).toBe(toBase64Url(new TextEncoder().encode(source)));
  });

  test('refuses past the cap on both paths, with an incompressible payload', async () => {
    // A compressible payload cannot prove the deflate path's refusal, so this
    // one is drawn from a seeded generator over the printable ASCII range.
    const noisy = incompressible(12000);
    const deflated = await encodeShare(noisy, zlibCodec);
    expect(deflated.ok).toBe(false);
    if (deflated.ok) return;
    expect(deflated.reason).toBe('too-large');
    expect(deflated.cap).toBe(SHARE_CAP);
    expect(deflated.chars).toBeGreaterThan(SHARE_CAP);

    const plain = await encodeShare(noisy, null);
    expect(plain.ok).toBe(false);
    if (plain.ok) return;
    expect(plain.chars).toBeGreaterThan(SHARE_CAP);
  });

  test('the complement: a repetitive payload passes deflated and fails plain', async () => {
    // This is why the cap case above has to be incompressible.
    const repetitive = 'not n(in=a)\n'.repeat(40960 / 12);
    const deflated = await encodeShare(repetitive, zlibCodec);
    expect(deflated.ok).toBe(true);
    if (deflated.ok) expect(deflated.chars).toBeLessThan(500);

    const plain = await encodeShare(repetitive, null);
    expect(plain.ok).toBe(false);
    if (!plain.ok) expect(plain.reason).toBe('too-large');
  });

  test('a codec that throws degrades to the plain key', async () => {
    const broken: DeflateCodec = {
      deflateRaw: async () => { throw new Error('nope'); },
      inflateRaw: async () => { throw new Error('nope'); },
    };
    const r = await encodeShare('input a\n', broken);
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.key).toBe('src0');
  });
});

describe('decodeShare', () => {
  test('reports every malformed payload as a value', async () => {
    expect(await decodeShare('#src=!!', zlibCodec)).toEqual({ ok: false, reason: 'bad-base64' });

    const notDeflate = toBase64Url(new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]));
    expect(await decodeShare(`#src=${notDeflate}`, zlibCodec)).toEqual({ ok: false, reason: 'bad-deflate' });

    // Valid deflate whose payload is not valid UTF-8.
    const badUtf8 = toBase64Url(new Uint8Array(deflateRawSync(Buffer.from([0xff, 0xfe, 0xff]))));
    expect(await decodeShare(`#src=${badUtf8}`, zlibCodec)).toEqual({ ok: false, reason: 'bad-utf8' });

    expect(await decodeShare('#src=AAAA', null)).toEqual({ ok: false, reason: 'no-codec' });
    expect(await decodeShare('#zz=1', zlibCodec)).toEqual({ ok: false, reason: 'unknown-key' });
    expect(await decodeShare('', zlibCodec)).toEqual({ ok: false, reason: 'no-key' });
    expect(await decodeShare('#', zlibCodec)).toEqual({ ok: false, reason: 'no-key' });
  });

  test('a plain key needs no codec', async () => {
    const r = await encodeShare('input a\n', null);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(await decodeShare(r.fragment, null)).toEqual({ ok: true, key: 'src0', source: 'input a\n' });
  });
});

describe('readHash', () => {
  test('reports every key it found', () => {
    expect(readHash('#src=AAA')).toEqual({ src: { key: 'src', payload: 'AAA' } });
    expect(readHash('#src0=BBB')).toEqual({ src: { key: 'src0', payload: 'BBB' } });
    // `#src=` wins over `#src0=`.
    expect(readHash('#src=A&src0=B').src).toEqual({ key: 'src', payload: 'A' });
    expect(readHash('#pick=tour:5')).toEqual({ pick: 'tour:5' });
    // Both are kept, so a failed decode can still reach the pick.
    const both = readHash('#src=A&pick=tour:5');
    expect(both.src).toEqual({ key: 'src', payload: 'A' });
    expect(both.pick).toBe('tour:5');
    // A leading # is optional.
    expect(readHash('pick=example:inverter')).toEqual({ pick: 'example:inverter' });
    // Nothing this phase reads.
    expect(readHash('')).toEqual({});
    expect(readHash('#')).toEqual({});
    expect(readHash('#other=1')).toEqual({ unknown: ['other'] });
  });

  test('a percent-encoded pick id is decoded', () => {
    expect(readHash('#pick=example%3Ahalf-adder').pick).toBe('example:half-adder');
  });
});

describe('shareUrl', () => {
  test('replaces the fragment and keeps path and query', () => {
    expect(shareUrl('https://x.dev/circ/playground?a=1#old', '#src=AAA')).toBe(
      'https://x.dev/circ/playground?a=1#src=AAA',
    );
    expect(shareUrl('https://x.dev/playground', '#src0=B')).toBe('https://x.dev/playground#src0=B');
  });

  test('a malformed href is returned unchanged rather than throwing', () => {
    expect(shareUrl('not a url', '#src=A')).toBe('not a url');
  });
});

describe('webStreamsCodec', () => {
  test('is null where the globals are absent', () => {
    // Under bun both globals are undefined, which is exactly the browser case
    // the `#src0=` fallback exists for.
    expect(webStreamsCodec()).toBeNull();
  });
});

describe('every shipped source survives a share round-trip under the cap', () => {
  test('through #src= and through #src0=', async () => {
    expect(sources).toHaveLength(17);
    for (const source of sources) {
      const deflated = await encodeShare(source, zlibCodec);
      expect(deflated.ok).toBe(true);
      if (!deflated.ok) continue;
      expect(deflated.chars).toBeLessThanOrEqual(SHARE_CAP);
      expect(await decodeShare(deflated.fragment, zlibCodec)).toEqual({
        ok: true,
        key: 'src',
        source,
      });

      const plain = await encodeShare(source, null);
      expect(plain.ok).toBe(true);
      if (!plain.ok) continue;
      expect(plain.chars).toBeLessThanOrEqual(SHARE_CAP);
      expect(await decodeShare(plain.fragment, null)).toEqual({ ok: true, key: 'src0', source });
    }
  });

  test('deflate is the shorter key for every shipped source', async () => {
    for (const source of sources) {
      const deflated = await encodeShare(source, zlibCodec);
      const plain = await encodeShare(source, null);
      if (!deflated.ok || !plain.ok) throw new Error('unexpected refusal');
      expect(deflated.chars).toBeLessThan(plain.chars);
    }
  });
});
