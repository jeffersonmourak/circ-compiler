import { describe, expect, test } from 'bun:test';
import { Window } from 'happy-dom';
import { installPageApi } from '../src/scripts/agent-tools/page-api.ts';
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

function dispatchTransition(window: Window, type: 'pagehide' | 'pageshow', persisted: boolean): void {
  const event = new window.Event(type);
  Object.defineProperty(event, 'persisted', { value: persisted });
  window.dispatchEvent(event);
}

async function withWindow(run: (window: Window) => Promise<void>): Promise<void> {
  const window = new Window();
  const globals = globalThis as Record<string, unknown>;
  const saved = new Map<string, unknown>();
  const keys = ['window', 'document', 'navigator', 'HTMLElement', 'Event', 'circPlayground'];
  for (const key of keys) {
    saved.set(key, globals[key]);
    globals[key] = key === 'window' ? window : (window as unknown as Record<string, unknown>)[key];
  }
  try {
    await run(window);
  } finally {
    for (const key of keys) {
      const value = saved.get(key);
      if (value === undefined) delete globals[key];
      else globals[key] = value;
    }
    window.close();
  }
}

describe('page API lifecycle', () => {
  test('pagehide preserves a bfcache page and disposes a reload', async () => {
    await withWindow(async (window) => {
      const root = window.document.createElement('div');
      const installation = installPageApi(root as unknown as HTMLElement, { readStatus: status, pageId: 'cached-page' });
      const retained = installation.api;

      window.dispatchEvent(new window.Event('unload'));
      expect((await retained.callTool('circ_get_status', {})).ok).toBe(true);

      dispatchTransition(window, 'pagehide', true);
      expect(await retained.callTool('circ_get_status', {})).toMatchObject({ ok: false, error: { code: 'PAGE_SUSPENDED' } });
      dispatchTransition(window, 'pageshow', true);
      expect(retained.pageId).toBe('cached-page');
      expect((await retained.callTool('circ_get_status', {})).ok).toBe(true);

      dispatchTransition(window, 'pagehide', false);
      expect(await retained.callTool('circ_get_status', {})).toMatchObject({ ok: false, error: { code: 'PAGE_DISPOSED' } });
      await installation.dispose();
    });
  });
});
