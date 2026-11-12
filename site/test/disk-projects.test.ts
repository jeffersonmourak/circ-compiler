import { afterEach, describe, expect, test } from 'bun:test';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DiskMirror, dirForName, diskId, isSafeDir, orderFiles, roundTrips, type DiskOp, type DiskProject } from '../src/utils/disk-projects.ts';
import { diskStorage, diskWorkspace, DiskFileSource, DISK_BACKING_KEY, type DiskApi, type ImageTransport } from '../src/scripts/disk-storage.ts';
import { execute } from '../src/scripts/sim-executor.ts';
import { SimSession } from '../src/scripts/sim-session.ts';
import { MEMORIES, evaluateRom, stubRuntime } from './sim-stub.ts';
import {
  createStore, createScratch, deleteScratch, renameScratch, touchScratch,
  liftStoreLimits, restoreStoreLimits, MAX_SCRATCH, MAX_SOURCE_BYTES, STORE_KEY, type StorageLike,
} from '../src/utils/playground-store.ts';
import { joinFiles } from '../src/utils/split-files.ts';
import { allowed, applyOps, readImage, resolveDir, resolveImage, scanProjects, writeImage, TRASH_DIR } from '../scripts/dev-playground/plugin.mjs';

const child = { name: 'child.circ', body: 'input a\nnot n(in=a)\noutput o(in=n.out)\n' };
const root = { name: 'top.circ', body: 'import child "child.circ"\ninput x\nchild c(a=x)\noutput z(in=c.o)\n' };
const pair = (dir: string, mtimeMs = 5): DiskProject => ({ dir, files: [root, child], mtimeMs });

describe('directories and names', () => {
  test('safe directories are plain segments', () => {
    for (const dir of ['.', 'a', 'a/b', 'sharp_cpu', 'v1.2/x-y']) expect(isSafeDir(dir)).toBe(true);
    for (const dir of ['', '..', 'a/../b', '/abs', 'a//b', '.hidden', 'a b']) expect(isSafeDir(dir)).toBe(false);
  });

  test('a project name maps to a directory', () => {
    expect(dirForName('adder')).toBe('adder');
    expect(dirForName('My Adder 2')).toBe('My-Adder-2');
    expect(dirForName('cpu/alu unit')).toBe('cpu/alu-unit');
    expect(dirForName('../../etc')).toBe('etc');
    expect(dirForName(' ?? ')).toBeNull();
  });

  test('the file nothing imports opens last', () => {
    expect(orderFiles('p', [root, child]).map((f) => f.name)).toEqual(['child.circ', 'top.circ']);
    const loose = [{ name: 'b.circ', body: '' }, { name: 'main.circ', body: '' }, { name: 'z.circ', body: '' }];
    expect(orderFiles('p', loose).map((f) => f.name)).toEqual(['b.circ', 'z.circ', 'main.circ']);
    const named = [{ name: 'a.circ', body: '' }, { name: 'sharp.circ', body: '' }, { name: 'z.circ', body: '' }];
    expect(orderFiles('x/sharp', named).at(-1)!.name).toBe('sharp.circ');
  });

  test('a marker-like comment mid-file does not round-trip', () => {
    expect(roundTrips([child, root])).toBe(true);
    expect(roundTrips([{ name: 'a.circ', body: '// a.circ\ninput a\n' }])).toBe(true);
    expect(roundTrips([{ name: 'a.circ', body: 'input a\n// b.circ\ninput b\n' }])).toBe(false);
    expect(roundTrips([{ name: 'bad name.circ', body: '' }])).toBe(false);
  });
});

describe('DiskMirror', () => {
  test('loading plans nothing', () => {
    const mirror = new DiskMirror();
    const { records, skipped } = mirror.load([pair('one'), pair('two')]);
    expect(skipped).toEqual([]);
    expect(records.map((r) => [r.id, r.name])).toEqual([[diskId('one'), 'one'], [diskId('two'), 'two']]);
    expect(mirror.plan(records)).toEqual({ ops: [], refused: null });
  });

  test('an edit writes only the file that changed', () => {
    const mirror = new DiskMirror();
    const { records } = mirror.load([pair('one')]);
    const edited = joinFiles([child, { ...root, body: root.body + '// more\n' }]);
    const { ops } = mirror.plan([{ ...records[0], source: edited }]);
    expect(ops).toEqual([{ op: 'write', dir: 'one', file: 'top.circ', body: root.body + '// more\n' }]);
    expect(mirror.plan([{ ...records[0], source: edited }]).ops).toEqual([]);
  });

  test('tabs added, renamed and deleted become file operations', () => {
    const mirror = new DiskMirror();
    const { records } = mirror.load([pair('one')]);
    const source = joinFiles([{ name: 'kid.circ', body: child.body }, { name: 'new.circ', body: 'input q\n' }, root]);
    const { ops } = mirror.plan([{ ...records[0], source }]);
    expect(ops).toContainEqual({ op: 'write', dir: 'one', file: 'kid.circ', body: child.body });
    expect(ops).toContainEqual({ op: 'write', dir: 'one', file: 'new.circ', body: 'input q\n' });
    expect(ops).toContainEqual({ op: 'remove', dir: 'one', file: 'child.circ' });
    expect(ops).toHaveLength(3);
  });

  test('a new project lands in a free directory and keeps it', () => {
    const mirror = new DiskMirror();
    const { records } = mirror.load([pair('one')]);
    const fresh = { id: 'scratch:abc', name: 'one', source: 'input a\n', updatedAt: 9 };
    const { ops } = mirror.plan([...records, fresh]);
    expect(ops).toEqual([{ op: 'write', dir: 'one-2', file: 'main.circ', body: 'input a\n' }]);
    expect(mirror.stableId('scratch:abc')).toBe(diskId('one-2'));
    expect(mirror.stableId('example:x')).toBe('example:x');
  });

  test('a rename moves the files; a taken name moves nothing', () => {
    const mirror = new DiskMirror();
    const { records } = mirror.load([pair('one'), pair('two')]);
    const moved = mirror.plan([{ ...records[0], name: 'cpu/core' }, records[1]]).ops;
    expect(moved.filter((o) => o.op === 'remove').map((o) => `${o.dir}/${o.file}`).sort()).toEqual(['one/child.circ', 'one/top.circ']);
    expect(moved.filter((o) => o.op === 'write').map((o) => `${o.dir}/${o.file}`).sort()).toEqual(['cpu/core/child.circ', 'cpu/core/top.circ']);
    expect(mirror.plan([{ ...records[0], name: 'two' }, records[1]]).ops).toEqual([]);
  });

  test('deleting one project removes its files; losing several is refused', () => {
    const mirror = new DiskMirror();
    const { records } = mirror.load([pair('one'), pair('two'), pair('three')]);
    const { ops } = mirror.plan([records[1], records[2]]);
    expect(ops.every((o) => o.op === 'remove' && o.dir === 'one')).toBe(true);
    expect(ops).toHaveLength(2);
    const refusal = mirror.plan([]);
    expect(refusal.ops).toEqual([]);
    expect(refusal.refused).toMatch(/2 projects/);
  });

  test('a project that cannot round-trip is left out and never written', () => {
    const mirror = new DiskMirror();
    const broken: DiskProject = { dir: 'odd', files: [{ name: 'a.circ', body: 'input a\n// b.circ\ninput b\n' }], mtimeMs: 1 };
    const { records, skipped } = mirror.load([broken, pair('one')]);
    expect(skipped.map((s) => s.dir)).toEqual(['odd']);
    expect(mirror.plan(records).ops).toEqual([]);
    const fresh = { id: 'scratch:n', name: 'odd', source: 'input a\n', updatedAt: 1 };
    expect(mirror.plan([...records, fresh]).ops[0]).toMatchObject({ dir: 'odd-2' });
  });
});

describe('diskStorage under the store', () => {
  afterEach(() => restoreStoreLimits());

  function harness(projects: DiskProject[]) {
    const applied: DiskOp[][] = [];
    const api: DiskApi = { list: () => projects, apply: async (ops) => { applied.push(ops); } };
    const data = new Map<string, string>();
    const backing: StorageLike = {
      getItem: (k) => data.get(k) ?? null,
      setItem: (k, v) => { data.set(k, v); },
      removeItem: (k) => { data.delete(k); },
    };
    const errors: string[] = [];
    const storage = diskStorage(backing, api, { onError: (m) => errors.push(m) });
    return { applied, data, errors, storage };
  }
  const settle = () => new Promise((r) => setTimeout(r, 0));

  test('projects come from disk; edits go back; nothing else is stored as source', async () => {
    liftStoreLimits();
    const h = harness([pair('one'), pair('two')]);
    const store = createStore({ storage: h.storage });
    expect(store.envelope.scratch.map((p) => p.name).sort()).toEqual(['one', 'two']);

    const id = diskId('one');
    const edited = joinFiles([child, { ...root, body: 'input x\noutput z(in=x)\n' }]);
    store.update((draft) => { draft.scratch = touchScratch(draft.scratch, id, edited, 10).list; draft.activeId = id; });
    store.flush();
    await settle();
    expect(h.applied).toEqual([[{ op: 'write', dir: 'one', file: 'top.circ', body: 'input x\noutput z(in=x)\n' }]]);

    expect(h.data.has(STORE_KEY)).toBe(false);
    const kept = JSON.parse(h.data.get(DISK_BACKING_KEY)!);
    expect(kept.scratch).toEqual([]);
    expect(kept.activeId).toBe(id);
    expect(h.errors).toEqual([]);
  });

  test('create, rename and delete reach the disk; a created project reloads under its directory id', async () => {
    liftStoreLimits();
    const h = harness([pair('one')]);
    const store = createStore({ storage: h.storage });
    let created = '';
    store.update((draft) => {
      const r = createScratch(draft.scratch, { name: 'Fresh One', source: 'input a\n', now: 20 });
      draft.scratch = r.list;
      created = r.created!.id;
      draft.activeId = created;
    });
    store.flush();
    store.update((draft) => { draft.scratch = renameScratch(draft.scratch, created, 'renamed'); });
    store.flush();
    store.update((draft) => { draft.scratch = deleteScratch(draft.scratch, diskId('one')); });
    store.flush();
    await settle();
    expect(h.applied[0]).toEqual([{ op: 'write', dir: 'Fresh-One', file: 'main.circ', body: 'input a\n' }]);
    expect(h.applied[1]).toEqual([
      { op: 'remove', dir: 'Fresh-One', file: 'main.circ' },
      { op: 'write', dir: 'renamed', file: 'main.circ', body: 'input a\n' },
    ]);
    expect(h.applied[2].map((o) => o.op)).toEqual(['remove', 'remove']);
    expect(JSON.parse(h.data.get(DISK_BACKING_KEY)!).activeId).toBe(diskId('renamed'));
  });

  test('the localStorage caps do not apply on disk', () => {
    liftStoreLimits();
    const many = Array.from({ length: MAX_SCRATCH + 9 }, (_, i) => pair(`p${String(i).padStart(2, '0')}`, i));
    many.push({ dir: 'big', files: [{ name: 'big.circ', body: `// ${'x'.repeat(MAX_SOURCE_BYTES + 10)}\n` }], mtimeMs: 1 });
    const h = harness(many);
    const store = createStore({ storage: h.storage });
    expect(store.envelope.scratch).toHaveLength(MAX_SCRATCH + 10);
    store.update((draft) => { draft.view = 'truth'; });
    expect(store.flush()!.note).toBeNull();
    expect(h.applied).toEqual([]);
    expect(h.errors).toEqual([]);
  });

  test('an unreachable dev server disables persistence instead of writing blind', () => {
    const api: DiskApi = { list: () => { throw new Error('down'); }, apply: async () => { throw new Error('unreachable'); } };
    const store = createStore({ storage: diskStorage(null, api) });
    expect(store.enabled).toBe(false);
    expect(store.envelope.scratch).toEqual([]);
  });
});

describe('the dev server side', () => {
  function workspace() {
    const dir = mkdtempSync(join(tmpdir(), 'circ-playground-'));
    mkdirSync(join(dir, 'one'));
    mkdirSync(join(dir, 'deep', 'two'), { recursive: true });
    mkdirSync(join(dir, 'node_modules', 'pkg'), { recursive: true });
    mkdirSync(join(dir, '.git'));
    writeFileSync(join(dir, 'one', 'top.circ'), root.body);
    writeFileSync(join(dir, 'one', 'child.circ'), child.body);
    writeFileSync(join(dir, 'one', 'notes.txt'), 'not a circuit');
    writeFileSync(join(dir, 'deep', 'two', 'a.circ'), 'input a\n');
    writeFileSync(join(dir, 'node_modules', 'pkg', 'x.circ'), 'input a\n');
    writeFileSync(join(dir, '.git', 'x.circ'), 'input a\n');
    return dir;
  }

  test('scan finds each directory of .circ files and skips vendored and hidden ones', () => {
    const dir = workspace();
    const found = scanProjects(dir) as DiskProject[];
    expect(found.map((p) => p.dir)).toEqual(['deep/two', 'one']);
    expect(found[1].files.map((f) => f.name).sort()).toEqual(['child.circ', 'top.circ']);
    expect(new DiskMirror().load(found).skipped).toEqual([]);
  });

  test('paths outside the workspace are refused', () => {
    const dir = workspace();
    expect(resolveDir(dir, '.')).toBe(dir);
    expect(resolveDir(dir, 'one')).toBe(join(dir, 'one'));
    for (const bad of ['..', '../x', 'one/../../x', '/etc', '', '.git', 7]) expect(resolveDir(dir, bad)).toBeNull();
    expect(() => applyOps(dir, [{ op: 'write', dir: '../x', file: 'a.circ', body: '' }])).toThrow(/refused directory/);
    expect(() => applyOps(dir, [{ op: 'write', dir: 'one', file: '../a.circ', body: '' }])).toThrow(/refused file/);
    expect(() => applyOps(dir, [{ op: 'write', dir: 'one', file: 'notes.txt', body: '' }])).toThrow(/refused file/);
  });

  test('a write lands; a remove goes to the trash and unlinks nothing', () => {
    const dir = workspace();
    applyOps(dir, [
      { op: 'write', dir: 'one', file: 'top.circ', body: 'input q\n' },
      { op: 'write', dir: 'brand/new', file: 'main.circ', body: 'input n\n' },
      { op: 'remove', dir: 'one', file: 'child.circ' },
      { op: 'remove', dir: 'one', file: 'never-there.circ' },
    ], 'STAMP');
    expect(readFileSync(join(dir, 'one', 'top.circ'), 'utf8')).toBe('input q\n');
    expect(readFileSync(join(dir, 'brand', 'new', 'main.circ'), 'utf8')).toBe('input n\n');
    expect(existsSync(join(dir, 'one', 'child.circ'))).toBe(false);
    expect(readFileSync(join(dir, TRASH_DIR, 'STAMP', 'one', 'child.circ'), 'utf8')).toBe(child.body);
    expect(readdirSync(join(dir, 'one')).sort()).toEqual(['notes.txt', 'top.circ']);
    expect((scanProjects(dir) as DiskProject[]).map((p) => p.dir)).toEqual(['brand/new', 'deep/two', 'one']);
  });
});

describe('load and save over the workspace', () => {
  function workspace() {
    const dir = mkdtempSync(join(tmpdir(), 'circ-playground-img-'));
    mkdirSync(join(dir, 'projects', 'cpu'), { recursive: true });
    mkdirSync(join(dir, 'mem'));
    writeFileSync(join(dir, 'projects', 'cpu', 'cpu.circ'), 'input a\n');
    writeFileSync(join(dir, 'mem', 'prog.bin'), Buffer.from([0x10, 0x21, 0x32, 0x43]));
    return dir;
  }
  /** The dev server's two image routes, called in-process. */
  const transportOver = (root: string): ImageTransport => (method, url, body) => {
    if (method === 'GET') {
      const params = new URLSearchParams(url.split('?')[1]);
      return { status: 200, text: JSON.stringify(readImage(root, params.get('dir'), params.get('path'))) };
    }
    const { dir, path, base64 } = JSON.parse(body!);
    const r = writeImage(root, dir, path, base64, 'STAMP');
    return { status: 200, text: JSON.stringify({ ok: r.ok, error: r.error }) };
  };

  test('a path resolves against the project and may not leave the workspace', () => {
    const dir = workspace();
    expect(resolveImage(dir, 'projects/cpu', 'ram.bin')).toBe(join(dir, 'projects', 'cpu', 'ram.bin'));
    expect(resolveImage(dir, 'projects/cpu', '../../mem/prog.bin')).toBe(join(dir, 'mem', 'prog.bin'));
    expect(resolveImage(dir, '.', 'mem/prog.bin')).toBe(join(dir, 'mem', 'prog.bin'));
    for (const bad of ['../../../etc/passwd', '/etc/passwd', '', '.git/config', `${TRASH_DIR}/x.bin`, '../..']) {
      expect(resolveImage(dir, 'projects/cpu', bad)).toBeNull();
    }
    expect(resolveImage(dir, '../x', 'a.bin')).toBeNull();
  });

  test('reads and writes spell their failures as --sim does', () => {
    const dir = workspace();
    expect(readImage(dir, 'projects/cpu', 'missing.bin')).toEqual({ ok: false, error: 'FileNotFound' });
    expect(readImage(dir, 'projects/cpu', '../../../outside.bin')).toEqual({ ok: false, error: 'AccessDenied' });
    expect(readImage(dir, '.', 'mem')).toEqual({ ok: false, error: 'IsDir' });
    expect(writeImage(dir, '.', 'mem', 'AA==')).toMatchObject({ ok: false, error: 'IsDir' });
    expect(writeImage(dir, '.', '../escape.bin', 'AA==')).toMatchObject({ ok: false, error: 'AccessDenied' });
  });

  test('a save replaces the file and keeps the old one in the trash', () => {
    const dir = workspace();
    expect(writeImage(dir, 'projects/cpu', '../../mem/prog.bin', Buffer.from([1, 2]).toString('base64'), 'STAMP').ok).toBe(true);
    expect([...readFileSync(join(dir, 'mem', 'prog.bin'))]).toEqual([1, 2]);
    expect([...readFileSync(join(dir, TRASH_DIR, 'STAMP', 'mem', 'prog.bin'))]).toEqual([0x10, 0x21, 0x32, 0x43]);
    expect(writeImage(dir, 'projects/cpu', 'new/deep.bin', 'AA==', 'STAMP').ok).toBe(true);
    expect(existsSync(join(dir, 'projects', 'cpu', 'new', 'deep.bin'))).toBe(true);
  });

  test('only this page may call the routes', () => {
    const req = (headers: Record<string, string>, method = 'GET') => ({ headers, method });
    expect(allowed(req({ host: 'localhost:4321' }))).toBe(true);
    expect(allowed(req({ host: 'localhost:4321', origin: 'http://localhost:4321' }))).toBe(true);
    expect(allowed(req({ host: 'localhost:4321', origin: 'https://evil.example' }))).toBe(false);
    expect(allowed(req({ host: 'localhost:4321', origin: 'null' }))).toBe(false);
    expect(allowed(req({ host: 'localhost:4321', 'content-type': 'text/plain' }, 'POST'))).toBe(false);
    expect(allowed(req({ host: 'localhost:4321', 'content-type': 'application/json' }, 'POST'))).toBe(true);
  });

  test('the console loads an image from disk and saves the memory back', async () => {
    const dir = workspace();
    const files = new DiskFileSource(() => 'projects/cpu', transportOver(dir));
    const session = await SimSession.build({ bytes: new Uint8Array([0]), load: async () => stubRuntime(MEMORIES, evaluateRom) });

    expect(await execute(session, files, 'load code ../../mem/prog.bin')).toEqual(['ok words=4']);
    expect(await execute(session, files, 'peek code 2')).toEqual(['ok 0x32 0xff']);
    expect(await execute(session, files, 'load code nope.bin')).toEqual(['err E_IO nope.bin: FileNotFound']);
    expect(await execute(session, files, 'load code ../../../x.bin')).toEqual(['err E_IO ../../../x.bin: AccessDenied']);

    expect(await execute(session, files, 'poke code 0 0x7f')).toEqual(['ok']);
    expect(await execute(session, files, 'save code out.bin')).toEqual(['ok words=16']);
    const saved = readFileSync(join(dir, 'projects', 'cpu', 'out.bin'));
    expect(saved.length).toBe(16);
    expect([...saved.subarray(0, 4)]).toEqual([0x7f, 0x21, 0x32, 0x43]);
  });

  test('a project that is not on disk resolves against the workspace root', () => {
    const dir = workspace();
    const ws = diskWorkspace(null, { list: () => [{ dir: 'projects/cpu', files: [{ name: 'cpu.circ', body: 'input a\n' }], mtimeMs: 1 }], apply: async () => {} });
    ws.storage.getItem(STORE_KEY);
    expect(ws.dirFor(diskId('projects/cpu'))).toBe('projects/cpu');
    expect(ws.dirFor('example:x')).toBeNull();
    const files = new DiskFileSource(() => ws.dirFor('example:x'), transportOver(dir));
    const r = files.read('mem/prog.bin');
    expect(r.ok && [...r.bytes]).toEqual([0x10, 0x21, 0x32, 0x43]);
  });
});
