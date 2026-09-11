// The `--sim` goldens, replayed in the browser's terms: each fixture's
// circuit compiled by the committed libcirc.wasm, loaded into the renderer's
// CircRuntime, driven by the executor over the fixture's script, with the
// repository's `tests/fixtures/mem/` as the file source. The reply must match
// `tests/fixtures/expected-sim/<name>.txt` byte for byte, handshake included.
// Only `UPDATE_GOLDENS=1 zig build test` may change a golden; this test reads.
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { CircRuntime } from 'circ-renderer';
import { callOp, instantiateLibcirc, type LibcircExports } from '../src/scripts/libcirc-abi.ts';
import { execute, handshake, type FileSource } from '../src/scripts/sim-executor.ts';
import { SimSession } from '../src/scripts/sim-session.ts';

const skip = process.env.SKIP_LIBCIRC_TEST === '1';
const REPO = resolve(import.meta.dir, '..', '..');
const wasmPath = resolve(import.meta.dir, '..', 'public', 'wasm', 'libcirc.wasm');

let cached: Promise<LibcircExports> | null = null;
const lib = () => (cached ??= instantiateLibcirc(readFileSync(wasmPath)));

async function artifact(root: string): Promise<Uint8Array> {
  const source = readFileSync(resolve(REPO, root), 'utf8');
  const out = callOp(await lib(), 'compile', { root: '/playground/main.circ', files: { '/playground/main.circ': source } });
  expect(out.status).toBe(0);
  return out.bytes;
}

// Floating pins after init, as `--sim` has them; no `bootLow` here.
const load = (bytes: Uint8Array) => CircRuntime.loadFromBytes(bytes, { noInitialPinDrive: true });
const hex = (bytes: Uint8Array) => Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');

/** The scripts name files relative to the repository root, as the CLI's cwd is. */
const repoFiles: FileSource = {
  read(path) {
    try {
      return { ok: true, bytes: new Uint8Array(readFileSync(resolve(REPO, path))) };
    } catch (e) {
      const code = (e as { code?: string }).code;
      return { ok: false, error: code === 'ENOENT' ? 'FileNotFound' : code === 'EACCES' ? 'AccessDenied' : String(code) };
    }
  },
  write(path) {
    throw new Error(`a fixture script must not save (${path})`);
  },
};

/** One row of `tests/sim/golden_test.zig`'s table. */
interface Fixture {
  name: string;
  /** The circuit the CLI was pointed at, relative to the repository root. */
  root: string;
  /** `--mem=<name>=<path>` preloads, as the golden test passes them. */
  preloads?: { mem: string; width: number; addrWidth: number; path: string }[];
}

async function transcript(fx: Fixture): Promise<string> {
  const roms = (fx.preloads ?? []).map((p) => ({ name: p.mem, kind: 'rom' as const, width: p.width, addrWidth: p.addrWidth }));
  const images = new Map((fx.preloads ?? []).map((p) => [p.mem, hex(new Uint8Array(readFileSync(resolve(REPO, p.path))))]));
  const session = await SimSession.build({ bytes: await artifact(fx.root), load, roms, images });
  const out = handshake(session, fx.root);
  const script = readFileSync(resolve(REPO, 'tests', 'fixtures', 'sim', `${fx.name}.script`), 'utf8');
  for (const line of script.split('\n')) out.push(...(await execute(session, repoFiles, line)));
  session.destroy();
  return `${out.join('\n')}\n`;
}

const golden = (name: string) => readFileSync(resolve(REPO, 'tests', 'fixtures', 'expected-sim', `${name}.txt`), 'utf8');

describe.skipIf(skip)('the four --sim transcripts replay byte for byte', () => {
  test('sim_and_gate', async () => {
    expect(await transcript({ name: 'sim_and_gate', root: 'tests/fixtures/circuits/and_gate.circ' })).toBe(golden('sim_and_gate'));
  });

  test('sim_rom_pc_walk, with its --mem preload', async () => {
    const fx: Fixture = {
      name: 'sim_rom_pc_walk',
      root: 'tests/fixtures/circuits/sim_rom_pc_walk.circ',
      preloads: [{ mem: 'code', width: 8, addrWidth: 4, path: 'tests/fixtures/mem/rom_pc_walk.bin' }],
    };
    expect(await transcript(fx)).toBe(golden('sim_rom_pc_walk'));
  });

  test('sim_ram_write_read', async () => {
    expect(await transcript({ name: 'sim_ram_write_read', root: 'tests/fixtures/circuits/sim_ram_write_read.circ' })).toBe(golden('sim_ram_write_read'));
  });

  test('sim_mem_errors', async () => {
    expect(await transcript({ name: 'sim_mem_errors', root: 'tests/fixtures/circuits/sim_ram_write_read.circ' })).toBe(golden('sim_mem_errors'));
  });
});
