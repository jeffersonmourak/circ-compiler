// Every verb's reply over the stub session, string by string against
// lib/sim/loop.zig, including the error arms the goldens do not reach.
import { describe, expect, test } from 'bun:test';
import { MemoryTabFiles } from '../src/scripts/console.ts';
import { execute, handshake, MemoryFileSource } from '../src/scripts/sim-executor.ts';
import { SimSession } from '../src/scripts/sim-session.ts';
import { AND_GATE, evaluateAnd, evaluateRom, MEMORIES, stubRuntime, type StubRuntime } from './sim-stub.ts';

async function andSession(warnings: SimSession['warnings'] = []) {
  let rt!: StubRuntime;
  const session = await SimSession.build({
    bytes: new Uint8Array(),
    load: async () => (rt = stubRuntime(AND_GATE, evaluateAnd)),
    warnings,
  });
  return { session, rt: () => rt };
}

async function memSession() {
  let rt!: StubRuntime;
  const session = await SimSession.build({
    bytes: new Uint8Array(),
    load: async () => (rt = stubRuntime(MEMORIES, evaluateRom)),
  });
  return { session, rt: () => rt };
}

const files = new MemoryFileSource();

/** Feed lines in order and collect every reply line, as a transcript would. */
async function replay(session: SimSession, source: MemoryFileSource, lines: string[]): Promise<string[]> {
  const out: string[] = [];
  for (const line of lines) out.push(...(await execute(session, source, line)));
  return out;
}

describe('the handshake counts warnings and lists pins', () => {
  test('warning-free', async () => {
    const { session } = await andSession();
    expect(handshake(session, 'main.circ')).toEqual(['ready proto=1 pins=3 warnings=0', 'pin a in 1', 'pin b in 1', 'pin out out 1']);
  });

  test('one warning, spelled with the file the CLI was given', async () => {
    const { session } = await andSession([{ code: 'W001', file: 'other.circ', line: 2, col: 1, message: "input 'c' is never used" }]);
    expect(handshake(session, 'main.circ')).toEqual([
      'ready proto=1 pins=3 warnings=1',
      'pin a in 1',
      'pin b in 1',
      'pin out out 1',
      "diag warning W001 main.circ:2:1 input 'c' is never used",
    ]);
  });
});

describe('every reply is the loop\'s string', () => {
  test('blank lines and comments print nothing; parse failures print their code', async () => {
    const { session } = await andSession();
    expect(await execute(session, files, '')).toEqual([]);
    expect(await execute(session, files, '# note')).toEqual([]);
    expect(await execute(session, files, 'frob')).toEqual(['err E_PROTO malformed command']);
    expect(await execute(session, files, 'set a zz')).toEqual(['err E_BADVAL invalid integer literal']);
  });

  test('pins, run, set, get and dump', async () => {
    const { session } = await andSession();
    expect(await execute(session, files, 'pins')).toEqual(['pins 3', 'pin a in 1', 'pin b in 1', 'pin out out 1']);
    expect(await execute(session, files, 'run')).toEqual(['ok']);
    expect(await execute(session, files, 'get out')).toEqual(['ok 0x0 0x0']);
    expect(await execute(session, files, 'set a 1')).toEqual(['ok']);
    expect(await execute(session, files, 'set b 1')).toEqual(['ok']);
    expect(await execute(session, files, 'get out')).toEqual(['ok 0x1 0x1']);
    // An input reads back as driven, outputs then inputs in the lookup.
    expect(await execute(session, files, 'get a')).toEqual(['ok 0x1 0x1']);
    expect(await execute(session, files, 'dump in')).toEqual(['vals 2', 'a 0x1 0x1', 'b 0x1 0x1']);
    expect(await execute(session, files, 'dump out')).toEqual(['vals 1', 'out 0x1 0x1']);
    expect(await execute(session, files, 'dump all')).toEqual(['vals 3', 'a 0x1 0x1', 'b 0x1 0x1', 'out 0x1 0x1']);
    // A masked set: the value bit under an unknown mask reads as 0.
    expect(await execute(session, files, 'set a 1 0')).toEqual(['ok']);
    expect(await execute(session, files, 'get a')).toEqual(['ok 0x0 0x0']);
  });

  test('the pin error arms', async () => {
    const { session } = await andSession();
    expect(await execute(session, files, 'set out 1')).toEqual(['err E_NOTIN out']);
    expect(await execute(session, files, 'set nope 1')).toEqual(['err E_NOPIN nope']);
    expect(await execute(session, files, 'set a 2')).toEqual(['err E_WIDTH a']);
    expect(await execute(session, files, 'set a 1 2')).toEqual(['err E_WIDTH a']);
    expect(await execute(session, files, 'get nope')).toEqual(['err E_NOPIN nope']);
  });

  test('eval drives nothing on a bad line, and spells its answers pin=value/defined', async () => {
    const { session, rt } = await andSession();
    expect(await execute(session, files, 'eval a=1 b=1 => out')).toEqual(['ok out=0x1/0x1']);
    expect(await execute(session, files, 'eval a=1 b=0 => out a b')).toEqual(['ok out=0x0/0x1 a=0x1/0x1 b=0x0/0x1']);
    expect(await execute(session, files, 'eval => out')).toEqual(['ok out=0x0/0x1']);
    expect(await execute(session, files, 'eval a=1 =>')).toEqual(['ok']);
    const before = rt().calls.length;
    expect(await execute(session, files, 'eval a=1 nope=1 => out')).toEqual(['err E_NOPIN nope']);
    expect(await execute(session, files, 'eval a=1 => nope')).toEqual(['err E_NOPIN nope']);
    expect(await execute(session, files, 'eval out=1 => out')).toEqual(['err E_NOTIN out']);
    expect(rt().calls.length).toBe(before);
  });

  test('reset and quit both start over; quit says goodbye', async () => {
    const { session, rt } = await andSession();
    await execute(session, files, 'set a 1');
    const first = rt();
    expect(await execute(session, files, 'reset')).toEqual(['ok']);
    expect(first.destroyed).toBe(true);
    expect(await execute(session, files, 'get a')).toEqual(['ok 0x0 0x0']);
    await execute(session, files, 'set a 1');
    const second = rt();
    expect(await execute(session, files, 'quit')).toEqual(['ok bye']);
    expect(second.destroyed).toBe(true);
    expect(await execute(session, files, 'get a')).toEqual(['ok 0x0 0x0']);
  });

  test('mems on a memory-free circuit is an empty block', async () => {
    const { session } = await andSession();
    expect(await execute(session, files, 'mems')).toEqual(['mems 0']);
  });

  test('mems, peek, poke, mem and clear', async () => {
    const { session } = await memSession();
    expect(await execute(session, files, 'mems')).toEqual(['mems 2', 'mem code rom 8 4', 'mem data ram 8 2']);
    expect(await execute(session, files, 'peek code 2')).toEqual(['ok 0x0 0x0']);
    expect(await execute(session, files, 'poke code 2 0xab')).toEqual(['ok']);
    expect(await execute(session, files, 'peek code 2')).toEqual(['ok 0xab 0xff']);
    expect(await execute(session, files, 'set pc 2')).toEqual(['ok']);
    expect(await execute(session, files, 'get q')).toEqual(['ok 0xab 0xff']);
    expect(await execute(session, files, 'poke code 3 0 0')).toEqual(['ok']);
    expect(await execute(session, files, 'peek code 3')).toEqual(['ok 0x0 0x0']);
    expect(await execute(session, files, 'mem code 0 3')).toEqual(['cells 3', '0x0 0x0 0x0', '0x1 0x0 0x0', '0x2 0xab 0xff']);
    expect((await execute(session, files, 'mem code'))[0]).toBe('cells 16');
    expect(await execute(session, files, 'mem code 0xe')).toEqual(['cells 2', '0xe 0x0 0x0', '0xf 0x0 0x0']);
    expect(await execute(session, files, 'mem code 0xe 100')).toEqual(['cells 2', '0xe 0x0 0x0', '0xf 0x0 0x0']);
    expect(await execute(session, files, 'mem code 0 0')).toEqual(['cells 0']);
    expect(await execute(session, files, 'clear code')).toEqual(['ok']);
    expect(await execute(session, files, 'get q')).toEqual(['ok 0x0 0x0']);
  });

  test('the memory error arms', async () => {
    const { session } = await memSession();
    expect(await execute(session, files, 'peek nosuch 0')).toEqual(['err E_NOMEM nosuch']);
    expect(await execute(session, files, 'peek code 16')).toEqual(['err E_ADDR code 0x10']);
    expect(await execute(session, files, 'mem code 0x10')).toEqual(['err E_ADDR code 0x10']);
    expect(await execute(session, files, 'poke code 16 1')).toEqual(['err E_ADDR code 0x10']);
    expect(await execute(session, files, 'poke code 0 0x100')).toEqual(['err E_WIDTH code']);
    expect(await execute(session, files, 'poke code 0 1 0x100')).toEqual(['err E_WIDTH code']);
    expect(await execute(session, files, 'clear nosuch')).toEqual(['err E_NOMEM nosuch']);
    expect(await execute(session, files, 'set code 1')).toEqual(['err E_NOPIN code']);
    expect(await execute(session, files, 'get code')).toEqual(['err E_NOPIN code']);
  });

  test('load and save through a file source', async () => {
    const { session } = await memSession();
    const source = new MemoryFileSource(new Map([['img.bin', new Uint8Array([0x10, 0x20, 0x30, 0x40])]]));
    expect(await execute(session, source, 'set pc 1')).toEqual(['ok']);
    expect(await execute(session, source, 'load code img.bin')).toEqual(['ok words=4']);
    // The presented address follows the load with no further set.
    expect(await execute(session, source, 'get q')).toEqual(['ok 0x20 0xff']);
    expect(await execute(session, source, 'set pc 7')).toEqual(['ok']);
    expect(await execute(session, source, 'get q')).toEqual(['ok 0x0 0x0']);
    expect(await execute(session, source, 'poke code 2 0xff 0x0f')).toEqual(['ok']);
    expect(await execute(session, source, 'save code out.bin')).toEqual(['ok words=16']);
    const saved = source.files.get('out.bin')!;
    expect(saved.length).toBe(16);
    expect(Array.from(saved.slice(0, 4))).toEqual([0x10, 0x20, 0x0f, 0x40]);
    expect(await execute(session, source, 'clear code')).toEqual(['ok']);
    expect(await execute(session, source, 'load code out.bin')).toEqual(['ok words=16']);
    expect(await execute(session, source, 'peek code 2')).toEqual(['ok 0xf 0xff']);
  });

  test('the load and save error arms, in the loop\'s order', async () => {
    const { session } = await memSession();
    const source = new MemoryFileSource(
      new Map([
        ['odd.bin', new Uint8Array(3)],
        ['many.bin', new Uint8Array(17)],
        ['wide.bin', new Uint8Array([0xff, 0xff])],
        ['huge.bin', new Uint8Array(0)],
      ]),
    );
    const refusing = {
      read: (path: string) => (path === 'huge.bin' ? { ok: false as const, error: 'FileTooBig' } : source.read(path)),
      write: () => ({ ok: false as const, error: 'AccessDenied' }),
    };
    // An unknown memory wins over a readable file.
    expect(await execute(session, refusing, 'load nosuch odd.bin')).toEqual(['err E_NOMEM nosuch']);
    expect(await execute(session, refusing, 'load code nope.bin')).toEqual(['err E_IO nope.bin: FileNotFound']);
    expect(await execute(session, refusing, 'load code huge.bin')).toEqual(['err E_MEMFMT huge.bin: image exceeds 16 MiB']);
    expect(await execute(session, refusing, 'load code many.bin')).toEqual(['err E_MEMFMT many.bin: 17 words exceed capacity 16']);
    // `data` is 8 wide: one byte per word, so odd.bin loads; a 12-bit rom would refuse it.
    expect(await execute(session, refusing, 'load data odd.bin')).toEqual(['ok words=3']);
    expect(await execute(session, refusing, 'load data many.bin')).toEqual(['err E_MEMFMT many.bin: 17 words exceed capacity 4']);
    expect(await execute(session, refusing, 'save nosuch out.bin')).toEqual(['err E_NOMEM nosuch']);
    expect(await execute(session, refusing, 'save code out.bin')).toEqual(['err E_IO out.bin: AccessDenied']);
    expect(await execute(session, refusing, 'load code')).toEqual(['err E_PROTO malformed command']);
  });

  test("the page's file source points at the memory panel, protocol-shaped", async () => {
    const { session } = await memSession();
    const page = new MemoryTabFiles();
    expect(await execute(session, page, 'load code x.bin')).toEqual(['err E_IO x.bin: load images in the memory panel']);
    expect(await execute(session, page, 'save code x.bin')).toEqual(['err E_IO x.bin: save images from the memory panel']);
    // The memory is still resolved first.
    expect(await execute(session, page, 'load nosuch x.bin')).toEqual(['err E_NOMEM nosuch']);
  });

  test('a script replays as one transcript', async () => {
    const { session } = await andSession();
    const lines = ['mems', 'set a 1', 'set b 1', 'get out', 'quit'];
    expect(await replay(session, files, lines)).toEqual(['mems 0', 'ok', 'ok', 'ok 0x1 0x1', 'ok bye']);
  });
});
