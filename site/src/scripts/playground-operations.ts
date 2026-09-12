import type { OperationId, OperationKind, OperationState, OperationSummary, WorkInputs } from './playground-contract.ts';
import { copyWorkInputs } from './playground-revisions.ts';

const TERMINAL = new Set<OperationState>(['succeeded', 'diagnostics', 'refused', 'failed', 'superseded']);
export const MAX_RETAINED_OPERATIONS = 128;
export const MAX_OPERATION_WAITS = 32;

export type OperationLookup =
  | { kind: 'found'; operation: OperationSummary }
  | { kind: 'not_found' }
  | { kind: 'expired' };

export type WaitOutcome =
  | { wait: 'terminal'; operation: OperationSummary }
  | { wait: 'timed_out'; operation: OperationSummary }
  | { wait: 'cancelled'; operation: OperationSummary };

type Listener = (operation: OperationSummary) => void;

function copy<T>(value: T): T { return JSON.parse(JSON.stringify(value)) as T; }

export class OperationStore {
  private sequence = 0;
  private activeWaits = 0;
  private readonly records = new Map<OperationId, OperationSummary>();
  private readonly listeners = new Map<OperationId, Set<Listener>>();

  constructor(
    private readonly pageId: string,
    private readonly now: () => number = Date.now,
    private readonly maxRetained = MAX_RETAINED_OPERATIONS,
  ) {}

  create(kind: OperationKind, inputs: WorkInputs): OperationSummary {
    const id = `${this.pageId}:operation:${++this.sequence}`;
    const operation: OperationSummary = {
      id, kind, inputs: copyWorkInputs(inputs), state: 'queued', createdAt: this.now(), startedAt: null, finishedAt: null,
      counts: null, failure: null, refusal: null, supersededBy: null, supersededReason: null,
      artifactId: null, sessionId: null, truthScope: null, truthPath: null,
    };
    this.records.set(id, operation);
    return copy(operation);
  }

  lookup(id: string): OperationLookup {
    const operation = this.records.get(id);
    if (operation) return { kind: 'found', operation: copy(operation) };
    return id.startsWith(`${this.pageId}:operation:`) && this.sequenceFor(id) <= this.sequence
      ? { kind: 'expired' }
      : { kind: 'not_found' };
  }

  start(id: OperationId): OperationSummary | null {
    const current = this.records.get(id);
    if (!current || current.state !== 'queued') return null;
    return this.update(id, (operation) => ({ ...operation, state: 'running', startedAt: this.now() }));
  }

  finish(id: OperationId, state: Exclude<OperationState, 'queued' | 'running'>, patch: Partial<OperationSummary> = {}): OperationSummary | null {
    const operation = this.update(id, (current) => ({ ...current, ...copy(patch), state, finishedAt: this.now() }));
    if (operation) this.evict();
    return operation;
  }

  supersede(id: OperationId, supersededBy: OperationId | null, reason: 'new_inputs' | 'new_request' | 'target_changed'): OperationSummary | null {
    return this.finish(id, 'superseded', { supersededBy, supersededReason: reason });
  }

  async wait(id: OperationId, timeoutMs: number, signal?: AbortSignal): Promise<WaitOutcome | OperationLookup> {
    const lookup = this.lookup(id);
    if (lookup.kind !== 'found') return lookup;
    if (TERMINAL.has(lookup.operation.state)) return { wait: 'terminal', operation: lookup.operation };
    if (timeoutMs === 0) return { wait: 'timed_out', operation: lookup.operation };
    if (this.activeWaits >= MAX_OPERATION_WAITS) throw new Error('WAIT_LIMIT');
    this.activeWaits += 1;
    return new Promise((resolve) => {
      let settled = false;
      const complete = (outcome: WaitOutcome) => {
        if (settled) return;
        settled = true;
        this.activeWaits -= 1;
        clearTimeout(timer);
        signal?.removeEventListener('abort', abort);
        this.listeners.get(id)?.delete(listener);
        resolve(outcome);
      };
      const listener: Listener = (operation) => complete({ wait: 'terminal', operation });
      const currentOperation = () => {
        const current = this.lookup(id);
        return current.kind === 'found' ? current.operation : lookup.operation;
      };
      const abort = () => complete({ wait: 'cancelled', operation: currentOperation() });
      const timer = setTimeout(() => {
        const current = this.lookup(id);
        complete({ wait: 'timed_out', operation: current.kind === 'found' ? current.operation : lookup.operation });
      }, timeoutMs);
      const subscribers = this.listeners.get(id) ?? new Set<Listener>();
      subscribers.add(listener);
      this.listeners.set(id, subscribers);
      const current = this.lookup(id);
      if (current.kind === 'found' && TERMINAL.has(current.operation.state)) listener(current.operation);
      else if (signal?.aborted) abort();
      else signal?.addEventListener('abort', abort, { once: true });
    });
  }

  private update(id: OperationId, mutate: (operation: OperationSummary) => OperationSummary): OperationSummary | null {
    const current = this.records.get(id);
    if (!current || TERMINAL.has(current.state)) return null;
    const next = mutate(current);
    this.records.set(id, next);
    if (TERMINAL.has(next.state)) {
      for (const listener of this.listeners.get(id) ?? []) listener(copy(next));
      this.listeners.delete(id);
    }
    return copy(next);
  }

  private evict(): void {
    const terminal = [...this.records.values()].filter((operation) => TERMINAL.has(operation.state));
    terminal.sort((left, right) => left.createdAt - right.createdAt || this.sequenceFor(left.id) - this.sequenceFor(right.id));
    while (terminal.length > this.maxRetained) {
      const oldest = terminal.shift();
      if (oldest) this.records.delete(oldest.id);
    }
  }

  private sequenceFor(id: string): number {
    const value = Number(id.slice(`${this.pageId}:operation:`.length));
    return Number.isSafeInteger(value) && value > 0 ? value : Number.POSITIVE_INFINITY;
  }
}
