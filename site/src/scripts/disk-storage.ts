// The dev playground's storage: the playground's own projects come from the
// workspace directory and every edit is written back to it. Everything else
// in the envelope (layout, settings, the open view) stays in localStorage
// under a key of its own, so the dev playground and `astro dev` do not
// overwrite each other's state on the shared localhost origin.
//
// The store is synchronous, so the first read is a synchronous request. That
// is acceptable here and nowhere else: this module loads only in the dev
// playground (`bun run playground`), never in a build.

import { STORE_KEY, STORE_VERSION, type StorageLike } from '../utils/playground-store.ts';
import { DiskMirror, type DiskOp, type DiskProject, type Skipped } from '../utils/disk-projects.ts';
import type { FileSource } from './sim-executor.ts';

export const DISK_BACKING_KEY = 'circ.playground.disk.v1';
export const DISK_API = '/__circ/fs';

export interface DiskApi {
  /** Synchronous; throws when the dev server does not answer. */
  list(): DiskProject[];
  apply(ops: DiskOp[]): Promise<void>;
}

export function httpDiskApi(base = DISK_API): DiskApi {
  return {
    list() {
      const request = new XMLHttpRequest();
      request.open('GET', `${base}/projects`, false);
      request.send();
      if (request.status !== 200) throw new Error(`dev playground: ${base}/projects answered ${request.status}`);
      return (JSON.parse(request.responseText) as { projects: DiskProject[] }).projects;
    },
    async apply(ops) {
      const response = await fetch(`${base}/apply`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ ops }),
        // A write flushed as the page unloads must still reach the disk.
        keepalive: true,
      });
      if (!response.ok) throw new Error(`${response.status} ${await response.text()}`);
    },
  };
}

export interface DiskStorageHooks {
  /** A write the disk refused or the mirror would not plan. */
  onError?(message: string): void;
  /** Directories left out of the workspace, with the reason. */
  onSkipped?(skipped: Skipped[]): void;
}

/** The storage, and the directory each project it loaded or created lives in. */
export interface DiskWorkspace {
  storage: StorageLike;
  dirFor(id: string | null): string | null;
}

export function diskStorage(backing: StorageLike | null, api: DiskApi, hooks: DiskStorageHooks = {}): StorageLike {
  return diskWorkspace(backing, api, hooks).storage;
}

export function diskWorkspace(backing: StorageLike | null, api: DiskApi, hooks: DiskStorageHooks = {}): DiskWorkspace {
  const mirror = new DiskMirror();
  // Writes go out in order: a later one must never land before an earlier one.
  let queue: Promise<void> = Promise.resolve();

  const storage: StorageLike = {
    getItem(key) {
      if (key !== STORE_KEY) return backing?.getItem(key) ?? null;
      // A failed listing throws, and the store then disables persistence for
      // the session: with no picture of the disk, nothing may be written.
      const { records, skipped } = mirror.load(api.list());
      if (skipped.length > 0) hooks.onSkipped?.(skipped);
      let base: Record<string, unknown> = {};
      try {
        const text = backing?.getItem(DISK_BACKING_KEY);
        if (text) base = JSON.parse(text) as Record<string, unknown>;
      } catch {
        base = {};
      }
      return JSON.stringify({ ...base, version: STORE_VERSION, scratch: records });
    },
    setItem(key, value) {
      if (key !== STORE_KEY) {
        backing?.setItem(key, value);
        return;
      }
      const envelope = JSON.parse(value) as { scratch?: unknown; activeId?: unknown };
      const records = Array.isArray(envelope.scratch) ? envelope.scratch : [];
      const { ops, refused } = mirror.plan(records);
      if (refused) hooks.onError?.(refused);
      if (ops.length > 0) {
        queue = queue
          .then(() => api.apply(ops))
          .catch((err) => hooks.onError?.(`could not write to disk: ${(err as Error).message}`));
      }
      // Sources live on disk only. The active id is stored as the one the
      // project will carry after a reload.
      const activeId = typeof envelope.activeId === 'string' ? mirror.stableId(envelope.activeId) : null;
      try {
        backing?.setItem(DISK_BACKING_KEY, JSON.stringify({ ...envelope, scratch: [], activeId }));
      } catch {
        /* Layout and settings are a convenience; the sources are on disk. */
      }
    },
    removeItem(key) {
      backing?.removeItem(key === STORE_KEY ? DISK_BACKING_KEY : key);
    },
  };
  return { storage, dirFor: (id) => mirror.dirFor(id) };
}

/** One synchronous JSON exchange with the dev server; `FileSource` is synchronous. */
export type ImageTransport = (method: 'GET' | 'POST', url: string, body?: string) => { status: number; text: string };

export const xhrImageTransport: ImageTransport = (method, url, body) => {
  const request = new XMLHttpRequest();
  request.open(method, url, false);
  if (body !== undefined) request.setRequestHeader('content-type', 'application/json');
  request.send(body);
  return { status: request.status, text: request.responseText };
};

const toBase64 = (bytes: Uint8Array): string => {
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
};
const fromBase64 = (text: string): Uint8Array => Uint8Array.from(atob(text), (c) => c.charCodeAt(0));

/**
 * The console's `load` and `save` over the workspace: a path is resolved
 * against the open project's directory, or against the workspace root for a
 * project that is not on disk. The site's playground refuses both verbs; the
 * dev playground is the one place a browser console may touch a file.
 */
export class DiskFileSource implements FileSource {
  constructor(
    private readonly dir: () => string | null,
    private readonly transport: ImageTransport = xhrImageTransport,
    private readonly base = DISK_API,
  ) {}

  read(path: string): { ok: true; bytes: Uint8Array } | { ok: false; error: string } {
    const query = new URLSearchParams({ dir: this.dir() ?? '.', path });
    try {
      const reply = this.transport('GET', `${this.base}/image?${query}`);
      if (reply.status !== 200) return { ok: false, error: 'Unexpected' };
      const body = JSON.parse(reply.text) as { ok: boolean; base64?: string; error?: string };
      return body.ok && typeof body.base64 === 'string'
        ? { ok: true, bytes: fromBase64(body.base64) }
        : { ok: false, error: body.error ?? 'Unexpected' };
    } catch {
      return { ok: false, error: 'ConnectionRefused' };
    }
  }

  write(path: string, bytes: Uint8Array): { ok: true } | { ok: false; error: string } {
    try {
      const reply = this.transport('POST', `${this.base}/image`, JSON.stringify({ dir: this.dir() ?? '.', path, base64: toBase64(bytes) }));
      if (reply.status !== 200) return { ok: false, error: 'Unexpected' };
      const body = JSON.parse(reply.text) as { ok: boolean; error?: string };
      return body.ok ? { ok: true } : { ok: false, error: body.error ?? 'Unexpected' };
    } catch {
      return { ok: false, error: 'ConnectionRefused' };
    }
  }
}
