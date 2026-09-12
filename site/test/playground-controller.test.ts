import { describe, expect, test } from 'bun:test';
import { ControllerDisposedError, createPlaygroundController } from '../src/scripts/playground-controller.ts';
import type { PlaygroundStatus } from '../src/scripts/playground-contract.ts';
import type { WorkspaceSnapshot } from '../src/scripts/playground-reads.ts';
import { OperationStore } from '../src/scripts/playground-operations.ts';

function status(): PlaygroundStatus {
  return {
    lifecycle: 'ready', bootstrapError: null,
    project: { id: 'example:half-adder', name: 'Half-adder', entryFile: 'main.circ', fileCount: 1 },
    view: 'live', compiler: { ready: true, loading: false, identity: null, simulationCompatible: null },
    reportedPipeline: { kind: 'live', analyzing: false, building: false, analyzePending: false, buildPending: false, errors: 0, warnings: 0, stale: false, failure: null },
    artifact: { present: true, bytes: 42 }, session: { present: false },
    provenance: { tracking: 'untracked', sourceRevision: null, buildRevision: null, sessionId: null },
    persistence: { enabled: true },
    agentAccess: { pageRegistry: 'available', native: { state: 'unsupported', apiVariant: null, reason: 'Unavailable.' } },
  };
}

describe('playground controller', () => {
  test('status_snapshot_is_detached', () => {
    const source = status();
    const controller = createPlaygroundController({ read: () => source });
    const first = controller.getStatus();
    first.project!.name = 'changed';
    first.agentAccess.native.reason = 'changed';
    expect(source.project!.name).toBe('Half-adder');
    expect(controller.getStatus().agentAccess.native.reason).toBe('Unavailable.');
  });

  test('status_preserves_untracked_provenance', () => {
    const controller = createPlaygroundController({ read: status });
    expect(controller.getStatus().provenance).toEqual({ tracking: 'untracked', sourceRevision: null, buildRevision: null, sessionId: null });
  });

  test('disposed_controller_rejects_reads', () => {
    const controller = createPlaygroundController({ read: status });
    controller.dispose();
    controller.dispose();
    expect(() => controller.getStatus()).toThrow(ControllerDisposedError);
  });

  test('workspace_reads_return_domain_errors_without_mutating_the_snapshot', () => {
    const workspace: WorkspaceSnapshot = {
      revision: 'workspace-1',
      projects: [{
        id: 'scratch:one', name: 'Draft', kind: 'scratch', active: true, sourceOrigin: 'active_buffer', selectedEntryFile: 'main.circ',
        version: { projectId: 'scratch:one', revision: 'project-1', sourceRevision: 'source-1', imageRevision: 'image-1' },
        files: [{ name: 'main.circ', body: 'input a\n' }],
      }],
    };
    const controller = createPlaygroundController({ read: status }, () => workspace);
    expect(controller.listProjects({})).toMatchObject({ ok: true, value: { workspaceRevision: 'workspace-1' } });
    expect(controller.readFile({ name: 'missing.circ' })).toMatchObject({ ok: false, error: { code: 'FILE_NOT_FOUND' } });
    expect(workspace.projects[0].files[0].body).toBe('input a\n');
  });

  test('waits observe terminal operations without starting work', async () => {
    const store = new OperationStore('page');
    const operation = store.create('compile', {
      target: { projectId: 'scratch:one', sourceRevision: 'source-1', entryFile: 'main.circ', targetEpoch: 'target-1' },
      optionsRevision: 'options-1', imageRevision: null, artifactId: null, liveStateRevision: null,
    });
    store.finish(operation.id, 'failed', { failure: { kind: 'transport', message: 'worker stopped', libraryStatus: null } });
    const controller = createPlaygroundController({ read: status }, undefined, store);
    expect(await controller.waitForOperation({ operationId: operation.id, timeoutMs: 0 })).toMatchObject({
      ok: true, value: { wait: 'terminal', operation: { state: 'failed' } },
    });
    expect(await controller.waitForOperation({ operationId: 'other:operation:1' })).toMatchObject({ ok: false, error: { code: 'OPERATION_NOT_FOUND' } });
  });

  test('waits report page lifecycle cancellation and release their subscription', async () => {
    const store = new OperationStore('page');
    const operation = store.create('compile', {
      target: { projectId: 'scratch:one', sourceRevision: 'source-1', entryFile: 'main.circ', targetEpoch: 'target-1' },
      optionsRevision: 'options-1', imageRevision: null, artifactId: null, liveStateRevision: null,
    });
    const controller = createPlaygroundController({ read: status }, undefined, store);
    const suspended = controller.waitForOperation({ operationId: operation.id });
    controller.cancelWaits('PAGE_SUSPENDED');
    expect(await suspended).toMatchObject({ ok: false, error: { code: 'PAGE_SUSPENDED' } });
    const disposed = controller.waitForOperation({ operationId: operation.id });
    controller.dispose();
    expect(await disposed).toMatchObject({ ok: false, error: { code: 'PAGE_DISPOSED' } });
    store.finish(operation.id, 'succeeded');
    expect(store.lookup(operation.id)).toMatchObject({ kind: 'found', operation: { state: 'succeeded' } });
  });
});
