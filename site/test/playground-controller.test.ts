import { describe, expect, test } from 'bun:test';
import { ControllerDisposedError, createPlaygroundController } from '../src/scripts/playground-controller.ts';
import type { PlaygroundStatus } from '../src/scripts/playground-contract.ts';

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
});
