// `bun test` proof over the COMMITTED public/wasm/libcirc.wasm: the module
// the site ships compiles what the site shows. Honours SKIP_LIBCIRC_TEST=1
// on hosts where the wasm32 runtime misbehaves (see pr-tests.yml).
import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { callOp, callVersion, instantiateLibcirc, type LibcircExports } from '../src/scripts/libcirc-abi.ts';
import { examples } from '../src/content/examples.ts';
import { tour } from '../src/content/tour.ts';
import { splitFiles, requestFor } from '../src/utils/split-files.ts';

const skip = process.env.SKIP_LIBCIRC_TEST === '1';
const wasmPath = resolve(import.meta.dir, '..', 'public', 'wasm', 'libcirc.wasm');
const manifest = JSON.parse(readFileSync(resolve(import.meta.dir, '..', 'public', 'wasm', 'libcirc.manifest.json'), 'utf8'));

let cached: Promise<LibcircExports> | null = null;
const lib = () => (cached ??= instantiateLibcirc(readFileSync(wasmPath)));
const text = (b: Uint8Array) => new TextDecoder().decode(b);
const single = (source: string) => ({ root: '/playground/main.circ', files: { '/playground/main.circ': source } });

const RUNTIME_IMPORTS = {
  env: {
    print: () => {}, printFmt: () => {}, flushBuffer: () => {},
    _log: () => {}, _log_flush: () => {}, _log_set_name: () => {},
    debugEnabled: () => 0, onDebugLog: () => {},
  },
};

describe.skipIf(skip)('libcirc.wasm', () => {
  test('circ_version matches the committed manifest', async () => {
    const w = await lib();
    const v = callVersion(w);
    expect(v.status).toBe(0);
    const json = JSON.parse(text(v.bytes));
    for (const key of ['version', 'revision', 'topology_version', 'full_version', 'parser', 'parser_runtime_sha256', 'grammar_sha256']) {
      expect(json[key]).toEqual(manifest[key]);
    }
    expect(manifest.bytes).toBe(readFileSync(wasmPath).length);
  });

  test('compiles the inverter into an artifact with both custom sections', async () => {
    const w = await lib();
    const out = callOp(w, 'compile', single(examples[0].source));
    expect(out.status).toBe(0);
    const mod = await WebAssembly.compile(out.bytes);
    const min = WebAssembly.Module.customSections(mod, 'circ.topology.v0.min');
    const full = WebAssembly.Module.customSections(mod, 'circ.topology.v0.full');
    expect(min.length).toBe(1);
    expect(full.length).toBe(1);
    expect(new Uint8Array(full[0])[4]).toBe(manifest.full_version);
    const names = WebAssembly.Module.exports(mod).map((e) => e.name);
    for (const n of ['topology_alloc', 'init', 'run', 'setPin', 'getOutputValue', 'getOutputDefined']) expect(names).toContain(n);

    // Drive it: the inverter's input is component 0 and its output component 1.
    const instance = await WebAssembly.instantiate(mod, RUNTIME_IMPORTS);
    const x = instance.exports as any;
    const topo = new Uint8Array(min[0]);
    const ptr = x.topology_alloc(topo.length);
    new Uint8Array(x.memory.buffer).set(topo, ptr);
    x.init();
    x.setPin(0, 1n, 1n);
    x.run();
    expect(x.getOutputValue(1)).toBe(0n);
    x.setPin(0, 0n, 1n);
    x.run();
    expect(x.getOutputValue(1)).toBe(1n);
  });

  test('compiles tour step 6 with the last // name.circ file as root', async () => {
    const w = await lib();
    const step = tour[5];
    const files = splitFiles(step.source);
    expect(files.map((f) => f.name)).toEqual(['half_adder.circ', 'root.circ']);
    const out = callOp(w, 'compile', requestFor(files));
    expect(out.status).toBe(0);
    const mod = await WebAssembly.compile(out.bytes);
    const full = new TextDecoder('latin1').decode(WebAssembly.Module.customSections(mod, 'circ.topology.v0.full')[0]);
    expect(full).toContain('ha1');
    expect(full).toContain('ha2');
    expect(full).toContain('half_adder');
  });

  test('a broken source yields status 1 with a syntax diagnostic', async () => {
    const w = await lib();
    const out = callOp(w, 'compile', single('input a\nnot n(in=a\n'));
    expect(out.status).toBe(1);
    const json = JSON.parse(text(out.bytes));
    expect(json.files[0].path).toBe('/playground/main.circ');
    const syntax = json.diagnostics.find((d: any) => d.code === 'syntax');
    expect(syntax.severity).toBe('error');
    expect(syntax.message).toBe("expected ')' to close the connection list");
    expect(syntax.range).toEqual({ start_line: 3, start_col: 1, end_line: 3, end_col: 2 });
  });
});
