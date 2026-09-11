// The `--sim` request grammar, in the browser.
//
// A copy of `lib/sim/protocol.zig`'s `parseLine`, verb by verb, so what the
// console accepts is what the CLI accepts: the same tokens, the same optional
// arguments, the same refusals in the same order. `parseValue` is
// `std.fmt.parseInt(u64, text, 0)` over `bigint`, with the standard library's
// rules copied rather than approximated — a leading sign, a base prefix only
// past two characters, no underscore at either end of the digits, interior
// underscores skipped, every digit checked against the base, and nothing past
// 64 bits.
//
// No session, no I/O: a line goes in and a command or one of three parse
// failures comes out. The executor turns commands into replies.

export type Which = 'in' | 'out' | 'all';

export interface Assign {
  pin: string;
  value: bigint;
  /** `null`: fully defined. */
  mask: bigint | null;
}

export type Command =
  | { verb: 'pins' }
  | { verb: 'run' }
  | { verb: 'reset' }
  | { verb: 'quit' }
  | { verb: 'mems' }
  | { verb: 'set'; pin: string; value: bigint; mask: bigint | null }
  | { verb: 'get'; pin: string }
  | { verb: 'dump'; which: Which }
  | { verb: 'eval'; assigns: Assign[]; queries: string[] }
  | { verb: 'load'; mem: string; path: string }
  | { verb: 'save'; mem: string; path: string }
  | { verb: 'peek'; mem: string; addr: bigint }
  | { verb: 'poke'; mem: string; addr: bigint; value: bigint; mask: bigint | null }
  | { verb: 'mem'; mem: string; start: bigint | null; count: bigint | null }
  | { verb: 'clear'; mem: string };

/**
 * Why a line did not parse. `empty` is a blank or a `#` comment (no reply);
 * `malformed` is `err E_PROTO malformed command`; `badval` is
 * `err E_BADVAL invalid integer literal`.
 */
export type ParseOutcome = { ok: true; command: Command } | { ok: false; reason: 'empty' | 'malformed' | 'badval' };

const U64_MAX = (1n << 64n) - 1n;

const digitOf = (c: string): number => {
  const code = c.charCodeAt(0);
  if (code >= 48 && code <= 57) return code - 48;
  if (code >= 97 && code <= 122) return code - 97 + 10;
  if (code >= 65 && code <= 90) return code - 65 + 10;
  return 99;
};

/**
 * `std.fmt.parseInt(u64, text, 0)`: `null` where Zig returns an error. A
 * negative literal is an overflow for an unsigned type — except `-0`, which
 * the standard library accepts as zero, so this does too.
 */
export function parseValue(text: string): bigint | null {
  if (text.length === 0) return null;
  let buf = text;
  let negative = false;
  if (buf[0] === '+') buf = buf.slice(1);
  else if (buf[0] === '-') {
    buf = buf.slice(1);
    negative = true;
  }
  if (buf.length === 0) return null;
  let base = 10n;
  let digits = buf;
  if (buf.length > 2 && buf[0] === '0') {
    const p = buf[1].toLowerCase();
    if (p === 'b') { base = 2n; digits = buf.slice(2); }
    else if (p === 'o') { base = 8n; digits = buf.slice(2); }
    else if (p === 'x') { base = 16n; digits = buf.slice(2); }
  }
  if (digits[0] === '_' || digits[digits.length - 1] === '_') return null;
  let acc = 0n;
  for (const c of digits) {
    if (c === '_') continue;
    const d = digitOf(c);
    if (d >= Number(base)) return null;
    acc = acc * base + BigInt(d);
    if (acc > U64_MAX) return null;
  }
  if (negative && acc !== 0n) return null;
  return acc;
}

/** The protocol's canonical spelling of a value: lowercase hex, `0x`-prefixed, no padding. */
export const writeHex = (v: bigint): string => `0x${v.toString(16)}`;

const parseWhich = (s: string): Which | null => (s === 'in' || s === 'out' || s === 'all' ? s : null);

class Bad extends Error {
  constructor(readonly reason: 'malformed' | 'badval') {
    super(reason);
  }
}
const malformed = () => new Bad('malformed');
/** A literal that must parse; the CLI reports a bad one before a later shape error. */
const value = (s: string): bigint => {
  const v = parseValue(s);
  if (v === null) throw new Bad('badval');
  return v;
};

/** Parse one request line, exactly as `parseLine` in `lib/sim/protocol.zig` does. */
export function parseLine(raw: string): ParseOutcome {
  const line = raw.replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, '');
  if (line.length === 0 || line[0] === '#') return { ok: false, reason: 'empty' };
  const tokens = line.split(/[ \t]+/);
  const verb = tokens[0];
  const rest = tokens.slice(1);
  const next = (): string | undefined => rest.shift();
  const done = () => { if (rest.length !== 0) throw malformed(); };
  const need = (): string => { const t = next(); if (t === undefined) throw malformed(); return t; };

  try {
    switch (verb) {
      // Zig checks no extras for these four.
      case 'pins': return { ok: true, command: { verb: 'pins' } };
      case 'run': return { ok: true, command: { verb: 'run' } };
      case 'reset': return { ok: true, command: { verb: 'reset' } };
      case 'quit': return { ok: true, command: { verb: 'quit' } };
      case 'mems': {
        done();
        return { ok: true, command: { verb: 'mems' } };
      }
      case 'load':
      case 'save': {
        const mem = need();
        const path = need();
        done();
        return { ok: true, command: { verb, mem, path } };
      }
      case 'peek': {
        const mem = need();
        const addr = need();
        done();
        return { ok: true, command: { verb: 'peek', mem, addr: value(addr) } };
      }
      case 'poke': {
        const mem = need();
        const addrStr = need();
        const valueStr = need();
        const addr = value(addrStr);
        const v = value(valueStr);
        let mask: bigint | null = null;
        const maskStr = next();
        if (maskStr !== undefined) {
          mask = value(maskStr);
          done();
        }
        return { ok: true, command: { verb: 'poke', mem, addr, value: v, mask } };
      }
      case 'mem': {
        const mem = need();
        let start: bigint | null = null;
        let count: bigint | null = null;
        const startStr = next();
        if (startStr !== undefined) {
          start = value(startStr);
          const countStr = next();
          if (countStr !== undefined) {
            count = value(countStr);
            done();
          }
        }
        return { ok: true, command: { verb: 'mem', mem, start, count } };
      }
      case 'clear': {
        const mem = need();
        done();
        return { ok: true, command: { verb: 'clear', mem } };
      }
      case 'get': {
        const pin = need();
        done();
        return { ok: true, command: { verb: 'get', pin } };
      }
      case 'dump': {
        const which = parseWhich(need());
        done();
        if (which === null) throw malformed();
        return { ok: true, command: { verb: 'dump', which } };
      }
      case 'set': {
        const pin = need();
        const valueStr = need();
        const v = value(valueStr);
        let mask: bigint | null = null;
        const maskStr = next();
        if (maskStr !== undefined) {
          mask = value(maskStr);
          done();
        }
        return { ok: true, command: { verb: 'set', pin, value: v, mask } };
      }
      case 'eval': {
        const assigns: Assign[] = [];
        const queries: string[] = [];
        let sawArrow = false;
        for (const tok of rest) {
          if (tok === '=>') {
            if (sawArrow) throw malformed();
            sawArrow = true;
            continue;
          }
          if (sawArrow) {
            queries.push(tok);
            continue;
          }
          const eq = tok.indexOf('=');
          if (eq <= 0) throw malformed();
          const pin = tok.slice(0, eq);
          const rhs = tok.slice(eq + 1);
          if (rhs.length === 0) throw malformed();
          const slash = rhs.indexOf('/');
          if (slash >= 0) assigns.push({ pin, value: value(rhs.slice(0, slash)), mask: value(rhs.slice(slash + 1)) });
          else assigns.push({ pin, value: value(rhs), mask: null });
        }
        if (!sawArrow) throw malformed();
        return { ok: true, command: { verb: 'eval', assigns, queries } };
      }
      default:
        throw malformed();
    }
  } catch (e) {
    if (e instanceof Bad) return { ok: false, reason: e.reason };
    throw e;
  }
}
