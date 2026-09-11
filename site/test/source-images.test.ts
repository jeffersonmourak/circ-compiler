import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { CircRuntime } from 'circ-renderer';
import { callOp, instantiateLibcirc } from '../src/scripts/libcirc-abi.ts';
import { SimSession } from '../src/scripts/sim-session.ts';
import { rowsForPins } from '../src/scripts/truth-view.ts';
import type { Analysis } from '../src/scripts/circ-diagnostics.ts';
import { normalizeSourceImages, sourceImageKey } from '../src/utils/source-images.ts';
import { defaultEnvelope, normalize, writeEnvelope, MAX_ENVELOPE_BYTES } from '../src/utils/playground-store.ts';

test('source image storage separates projects and files and restores version-2 state', () => {
  const key = sourceImageKey('scratch:one', 'test.circ');
  const env = defaultEnvelope();
  env.sourceImages[key] = { code: 'ab cd' };
  expect(normalize(JSON.parse(JSON.stringify(env))).envelope.sourceImages[key]).toEqual({ code: 'ab cd' });
  expect(key).not.toBe(sourceImageKey('scratch:two', 'test.circ'));
  expect(key).not.toBe(sourceImageKey('scratch:one', 'main.circ'));
  expect(normalizeSourceImages({ [key]: { code: 'ff', bad: 7 }, invalid: [] })).toEqual({ [key]: { code: 'ff' } });
  expect(normalize({ version: 2 }).envelope.sourceImages).toEqual({});
  env.sourceImages[key].code = 'ff'.repeat(MAX_ENVELOPE_BYTES);
  let saved = '';
  const result = writeEnvelope(env, { getItem: () => null, setItem: (_, text) => { saved = text; }, removeItem: () => {} });
  expect(result.note).toEqual({ kind: 'images-skipped' });
  expect(JSON.parse(saved).sourceImages).toEqual({});
  expect(env.sourceImages[key].code.length).toBe(2 * MAX_ENVELOPE_BYTES);
});

test.skipIf(process.env.SKIP_LIBCIRC_TEST === '1')('source ROM images reach repeated nested instances, reset and complete Truth rows', async () => {
  const compiler = await instantiateLibcirc(readFileSync(resolve(import.meta.dir, '../public/wasm/libcirc.wasm')));
  const request = {
    root: '/playground/main.circ',
    files: {
      '/playground/test.circ': 'input[4] pc\nrom code[8, 4](addr=pc)\noutput[8] out(in=code)\n',
      '/playground/other.circ': 'input[4] pc\nrom code[8, 4](addr=pc)\noutput[8] out(in=code)\n',
      '/playground/wrapper.circ': 'import mem "test.circ"\ninput[4] pc\nmem a(pc=pc)\noutput[8] out(in=a)\n',
      '/playground/main.circ': 'import mem "wrapper.circ"\nimport other "other.circ"\ninput[4] pc\nmem a(pc=pc)\nmem b(pc=pc)\nother c(pc=pc)\noutput[8] x(in=a)\noutput[8] y(in=b)\noutput[8] z(in=c)\n',
    },
  };
  const analyzed = callOp(compiler, 'analyze', request);
  const analysis = JSON.parse(new TextDecoder().decode(analyzed.bytes)) as Analysis;
  const compiled = callOp(compiler, 'compile', request);
  expect(compiled.status).toBe(0);
  const childImages = new Map([['code', 'ab cd']]);
  const init = {
    bytes: compiled.bytes,
    load: (bytes: Uint8Array) => CircRuntime.loadFromBytes(bytes, { noInitialPinDrive: true }),
    importedImages: {
      files: new Map(analysis.files.map((f) => [f.file_id, f.path])),
      images: new Map([
        ['/playground/test.circ', childImages],
        ['/playground/other.circ', new Map([['code', '12 34']])],
      ]),
    },
  };
  const session = await SimSession.build(init);
  try {
    expect(session.mems).toEqual([]);
    session.set('pc', 0n);
    expect(session.get('x')).toMatchObject({ ok: true, value: { value: 0xabn, defined: 255n } });
    expect(session.get('y')).toMatchObject({ ok: true, value: { value: 0xabn, defined: 255n } });
    expect(session.get('z')).toMatchObject({ ok: true, value: { value: 0x12n, defined: 255n } });
    session.set('pc', 1n);
    expect(session.get('x')).toMatchObject({ ok: true, value: { value: 0xcdn } });
    const memories = session.runtime.topology.components.filter((c) => c.kind === 8);
    session.runtime.writeMemWord(memories[0].id, 0, 0n, 255n);
    expect(session.runtime.readMemWord(memories[1].id, 0).value).toBe(0xabn);
    await session.reset();
    session.set('pc', 0n);
    expect(session.get('x')).toMatchObject({ ok: true, value: { value: 0xabn } });
    const scratch = await SimSession.build(init);
    try {
      const outcome = rowsForPins(scratch, scratch, 4);
      expect(outcome.ok).toBe(true);
      if (outcome.ok) {
        expect(outcome.table.rows).toHaveLength(16);
        expect(outcome.table.rows[0].out).toEqual([0xabn, 0xabn, 0x12n]);
        expect(outcome.table.rows[1].out).toEqual([0xcdn, 0xcdn, 0x34n]);
        expect(outcome.table.rows[2].out).toEqual([null, null, null]);
      }
    } finally { scratch.destroy(); }
    childImages.set('code', 'not hex');
    expect(session.applyPreloads().errors.size).toBe(2);
    childImages.set('code', '');
    expect(session.applyPreloads().errors.size).toBe(0);
    session.run();
    expect(session.get('x')).toMatchObject({ ok: true, value: { defined: 0n } });
  } finally { session.destroy(); }
});
