import { describe, expect, test } from 'bun:test';
import { OperationStore } from '../src/scripts/playground-operations.ts';
import type { WorkInputs } from '../src/scripts/playground-contract.ts';

const inputs: WorkInputs = {
  target: { projectId: 'example:one', sourceRevision: 'source', entryFile: 'main.circ', targetEpoch: 'target' },
  optionsRevision: 'options', imageRevision: null, artifactId: null, liveStateRevision: null,
};

describe('playground operations', () => {
  test('queued_replacement_is_terminal', () => {
    const store = new OperationStore('page', () => 10);
    const first = store.create('analyze', inputs);
    const second = store.create('analyze', inputs);
    const result = store.supersede(first.id, second.id, 'new_request');
    expect(result).toMatchObject({ state: 'superseded', supersededBy: second.id, finishedAt: 10 });
    expect(store.start(first.id)).toBeNull();
  });

  test('terminal_operation_cannot_be_rewritten', () => {
    const store = new OperationStore('page');
    const operation = store.create('compile', inputs);
    store.supersede(operation.id, null, 'new_inputs');
    expect(store.finish(operation.id, 'succeeded')).toBeNull();
    const lookup = store.lookup(operation.id);
    expect(lookup.kind === 'found' && lookup.operation.state).toBe('superseded');
  });

  test('wait_has_no_lost_completion_window', async () => {
    const store = new OperationStore('page');
    const operation = store.create('compile', inputs);
    const waiting = store.wait(operation.id, 1000);
    store.finish(operation.id, 'succeeded');
    const result = await waiting;
    expect(result).toMatchObject({ wait: 'terminal', operation: { id: operation.id, state: 'succeeded' } });
  });

  test('timeout_does_not_finalize_work_and_abort_cancels_only_the_wait', async () => {
    const store = new OperationStore('page');
    const operation = store.create('compile', inputs);
    expect(await store.wait(operation.id, 0)).toMatchObject({ wait: 'timed_out', operation: { state: 'queued' } });
    const aborter = new AbortController();
    const waiting = store.wait(operation.id, 1000, aborter.signal);
    aborter.abort();
    expect(await waiting).toMatchObject({ wait: 'cancelled', operation: { state: 'queued' } });
    expect(store.lookup(operation.id)).toMatchObject({ kind: 'found', operation: { state: 'queued' } });
  });

  test('retention_expires_old_terminal_records_without_evicting_live_work', () => {
    const store = new OperationStore('page', () => 1, 1);
    const first = store.create('compile', inputs);
    const running = store.create('analyze', inputs);
    store.start(running.id);
    store.finish(first.id, 'succeeded');
    const second = store.create('preview', inputs);
    store.finish(second.id, 'succeeded');
    expect(store.lookup(first.id).kind).toBe('expired');
    expect(store.lookup(running.id)).toMatchObject({ kind: 'found', operation: { state: 'running' } });
  });
});
