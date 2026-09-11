// The request grammar, against lib/sim/protocol.zig's own tests and the
// standard library's parseInt cases, so the console refuses and accepts
// exactly what the CLI does.
import { describe, expect, test } from 'bun:test';
import { parseLine, parseValue, writeHex } from '../src/scripts/sim-protocol.ts';

const cmd = (line: string) => {
  const r = parseLine(line);
  if (!r.ok) throw new Error(`${line}: ${r.reason}`);
  return r.command;
};
const reason = (line: string) => {
  const r = parseLine(line);
  return r.ok ? 'ok' : r.reason;
};

describe('parseValue is std.fmt.parseInt(u64, text, 0)', () => {
  test('bases by prefix, decimal by default, case-insensitive digits and prefixes', () => {
    expect(parseValue('12')).toBe(12n);
    expect(parseValue('0x0c')).toBe(12n);
    expect(parseValue('0X0C')).toBe(12n);
    expect(parseValue('0b1100')).toBe(12n);
    expect(parseValue('0o14')).toBe(12n);
    expect(parseValue('0')).toBe(0n);
    expect(parseValue('050124')).toBe(50124n);
    expect(parseValue('DeadBeef')).toBeNull(); // hex digits in base 10
    expect(parseValue('0xDeadBeef')).toBe(0xdeadbeefn);
  });

  test('underscores group digits, but not at either end', () => {
    expect(parseValue('65_535')).toBe(65535n);
    expect(parseValue('0x0f_fff_fff_fff_fff_fff')).toBe(0xffffffffffffffffn);
    expect(parseValue('_10_')).toBeNull();
    expect(parseValue('0x_10_')).toBeNull();
    expect(parseValue('0x10_')).toBeNull();
    expect(parseValue('0x_10')).toBeNull();
    expect(parseValue('1__0')).toBe(10n);
  });

  test('a sign is allowed, and a negative value is an overflow except zero', () => {
    expect(parseValue('+10')).toBe(10n);
    expect(parseValue('-0')).toBe(0n);
    expect(parseValue('+0')).toBe(0n);
    expect(parseValue('-10')).toBeNull();
    expect(parseValue('+')).toBeNull();
    expect(parseValue('-')).toBeNull();
  });

  test('a prefix needs digits after it, and whitespace is not a digit', () => {
    expect(parseValue('0x')).toBeNull();
    expect(parseValue('0b')).toBeNull();
    expect(parseValue(' 10')).toBeNull();
    expect(parseValue('10 ')).toBeNull();
    expect(parseValue('')).toBeNull();
    expect(parseValue('1e3')).toBeNull();
    expect(parseValue('0b102')).toBeNull();
    expect(parseValue('0o8')).toBeNull();
  });

  test('sixty-four bits and not one more', () => {
    expect(parseValue('0xffffffffffffffff')).toBe((1n << 64n) - 1n);
    expect(parseValue('18446744073709551615')).toBe((1n << 64n) - 1n);
    expect(parseValue('18446744073709551616')).toBeNull();
    expect(parseValue('0x10000000000000000')).toBeNull();
  });

  test('writeHex is lowercase, prefixed, unpadded', () => {
    expect(writeHex(0n)).toBe('0x0');
    expect(writeHex(0x1fn)).toBe('0x1f');
    expect(writeHex(0xffn)).toBe('0xff');
    expect(writeHex((1n << 64n) - 1n)).toBe('0xffffffffffffffff');
  });
});

describe('parseLine mirrors lib/sim/protocol.zig', () => {
  test('blank lines and comments are empty, not errors', () => {
    expect(reason('')).toBe('empty');
    expect(reason('   \t ')).toBe('empty');
    expect(reason('# a comment')).toBe('empty');
    expect(reason('  # indented comment')).toBe('empty');
  });

  test('the four bare verbs, and mems which refuses extras', () => {
    expect(cmd('pins')).toEqual({ verb: 'pins' });
    expect(cmd('run')).toEqual({ verb: 'run' });
    expect(cmd('reset')).toEqual({ verb: 'reset' });
    expect(cmd('quit')).toEqual({ verb: 'quit' });
    // The Zig parser does not look past these four verbs.
    expect(cmd('pins extra')).toEqual({ verb: 'pins' });
    expect(cmd('mems')).toEqual({ verb: 'mems' });
    expect(reason('mems extra')).toBe('malformed');
  });

  test('set takes a value and an optional mask', () => {
    expect(cmd('set a 1')).toEqual({ verb: 'set', pin: 'a', value: 1n, mask: null });
    expect(cmd('set bus 0x5 0xf')).toEqual({ verb: 'set', pin: 'bus', value: 5n, mask: 15n });
    expect(cmd('set a 0 0')).toEqual({ verb: 'set', pin: 'a', value: 0n, mask: 0n });
    expect(reason('set a')).toBe('malformed');
    expect(reason('set a zz')).toBe('badval');
    expect(reason('set a 1 2 3')).toBe('malformed');
    // A bad value is reported before a shape error further along.
    expect(reason('set a zz 2 3')).toBe('badval');
  });

  test('get, dump and clear take exactly one argument', () => {
    expect(cmd('get out')).toEqual({ verb: 'get', pin: 'out' });
    expect(reason('get')).toBe('malformed');
    expect(reason('get a b')).toBe('malformed');
    expect(cmd('dump in')).toEqual({ verb: 'dump', which: 'in' });
    expect(cmd('dump all')).toEqual({ verb: 'dump', which: 'all' });
    expect(reason('dump sideways')).toBe('malformed');
    expect(reason('dump')).toBe('malformed');
    expect(cmd('clear code')).toEqual({ verb: 'clear', mem: 'code' });
    expect(reason('clear code 1')).toBe('malformed');
  });

  test('eval is assignments, one arrow, queries', () => {
    expect(cmd('eval a=3 b=0xf/0xf => out cout')).toEqual({
      verb: 'eval',
      assigns: [{ pin: 'a', value: 3n, mask: null }, { pin: 'b', value: 15n, mask: 15n }],
      queries: ['out', 'cout'],
    });
    expect(cmd('eval => out')).toEqual({ verb: 'eval', assigns: [], queries: ['out'] });
    expect(cmd('eval a=1 =>')).toEqual({ verb: 'eval', assigns: [{ pin: 'a', value: 1n, mask: null }], queries: [] });
    expect(reason('eval a=1')).toBe('malformed');
    expect(reason('eval a=1 => out => x')).toBe('malformed');
    expect(reason('eval =1 => out')).toBe('malformed');
    expect(reason('eval a= => out')).toBe('malformed');
    expect(reason('eval a => out')).toBe('malformed');
    expect(reason('eval a=zz => out')).toBe('badval');
    expect(reason('eval a=1/q => out')).toBe('badval');
  });

  test('the memory verbs', () => {
    expect(cmd('load code prog.bin')).toEqual({ verb: 'load', mem: 'code', path: 'prog.bin' });
    expect(cmd('save code out.bin')).toEqual({ verb: 'save', mem: 'code', path: 'out.bin' });
    expect(reason('load code')).toBe('malformed');
    expect(reason('load code a b')).toBe('malformed');
    expect(cmd('peek code 3')).toEqual({ verb: 'peek', mem: 'code', addr: 3n });
    expect(reason('peek code')).toBe('malformed');
    expect(reason('peek code x')).toBe('badval');
    expect(reason('peek code 1 2')).toBe('malformed');
    expect(cmd('poke data 0 0x1ff')).toEqual({ verb: 'poke', mem: 'data', addr: 0n, value: 0x1ffn, mask: null });
    expect(cmd('poke data 6 0x7f 0xff')).toEqual({ verb: 'poke', mem: 'data', addr: 6n, value: 0x7fn, mask: 0xffn });
    expect(reason('poke data 6')).toBe('malformed');
    expect(reason('poke data 6 1 2 3')).toBe('malformed');
    expect(cmd('mem code')).toEqual({ verb: 'mem', mem: 'code', start: null, count: null });
    expect(cmd('mem code 2')).toEqual({ verb: 'mem', mem: 'code', start: 2n, count: null });
    expect(cmd('mem code 2 3')).toEqual({ verb: 'mem', mem: 'code', start: 2n, count: 3n });
    expect(reason('mem code 2 3 4')).toBe('malformed');
    expect(reason('mem')).toBe('malformed');
  });

  test('an unknown verb is malformed, and tabs separate tokens too', () => {
    expect(reason('frobnicate')).toBe('malformed');
    expect(cmd('set\ta\t1')).toEqual({ verb: 'set', pin: 'a', value: 1n, mask: null });
    expect(cmd('  get   out  \r')).toEqual({ verb: 'get', pin: 'out' });
  });
});
