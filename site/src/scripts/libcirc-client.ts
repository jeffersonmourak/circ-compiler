// Main-thread handle on the playground's compiler worker: one promise per
// message id, lazy worker spawn, no timing policy (the component debounces).
import type { CallOp, LibcircRequest } from './libcirc-abi.ts';
import type { Op, WorkerMsg, WorkerReply } from '../workers/libcirc.worker.ts';

export type { CallOp, LibcircRequest, WorkerReply };

export interface LibcircVersion {
  version: string;
  revision: string;
  topology_version: number;
  full_version: number;
  parser: string;
  parser_runtime_sha256: string;
  grammar_sha256: string;
}

type Pending = { resolve: (r: WorkerReply) => void; reject: (e: Error) => void };

export class LibcircClient {
  private worker: Worker | null = null;
  private pending = new Map<number, Pending>();
  private nextId = 1;
  private initPromise: Promise<LibcircVersion> | null = null;

  constructor(private readonly wasmUrl: string) {}

  private spawn(): Worker {
    if (this.worker) return this.worker;
    const worker = new Worker(new URL('../workers/libcirc.worker.ts', import.meta.url), { type: 'module' });
    worker.onmessage = (ev: MessageEvent<WorkerReply>) => {
      const p = this.pending.get(ev.data.id);
      if (!p) return;
      this.pending.delete(ev.data.id);
      p.resolve(ev.data);
    };
    worker.onerror = (ev) => {
      const err = new Error(ev.message || 'libcirc worker crashed');
      for (const p of this.pending.values()) p.reject(err);
      this.pending.clear();
    };
    this.worker = worker;
    return worker;
  }

  private send(msg: Omit<WorkerMsg, 'id'>): Promise<WorkerReply> {
    const id = this.nextId++;
    const worker = this.spawn();
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      worker.postMessage({ id, ...msg } satisfies WorkerMsg);
    });
  }

  /** Spawns the worker on first call; resolves after circ_version(). */
  init(): Promise<LibcircVersion> {
    return (this.initPromise ??= this.send({ op: 'init', wasmUrl: this.wasmUrl }).then((r) => {
      if (r.status !== 0 || !r.text) throw new Error(r.error ?? `libcirc init failed (status ${r.status})`);
      return JSON.parse(r.text) as LibcircVersion;
    }));
  }

  async call(op: CallOp, request: LibcircRequest): Promise<WorkerReply> {
    await this.init();
    return this.send({ op, request });
  }

  async reset(): Promise<void> {
    await this.init();
    await this.send({ op: 'reset' as Op });
  }

  dispose(): void {
    const err = new Error('libcirc client disposed');
    for (const p of this.pending.values()) p.reject(err);
    this.pending.clear();
    this.worker?.terminate();
    this.worker = null;
    this.initPromise = null;
  }
}
