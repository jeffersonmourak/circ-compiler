import type { PlaygroundPageApi, PlaygroundStatus, StatusReader } from '../playground-contract.ts';
import { createPlaygroundController } from '../playground-controller.ts';
import { AgentToolRegistry } from './registry.ts';
import { statusDescriptor, statusHandler } from './status.ts';
import { WebMcpAdapter, detectNativeRegistrar } from '../webmcp-adapter.ts';

export interface PageApiInstallation {
  readonly api: PlaygroundPageApi;
  readonly registry: AgentToolRegistry;
  readonly native: WebMcpAdapter;
  dispose(): Promise<void>;
}

export interface InstallPageApiOptions {
  readStatus: () => PlaygroundStatus;
  pageId?: string;
  native?: WebMcpAdapter;
}

declare global {
  interface Window {
    circPlayground?: PlaygroundPageApi;
  }
}

const installs = new WeakMap<HTMLElement, PageApiInstallation>();
const facadeHost = globalThis as typeof globalThis & { circPlayground?: PlaygroundPageApi };

function pageId(): string {
  return globalThis.crypto?.randomUUID?.() ?? `circ-page-${Math.random().toString(36).slice(2)}`;
}

export function installPageApi(el: HTMLElement, options: InstallPageApiOptions): PageApiInstallation {
  const installed = installs.get(el);
  if (installed) return installed;
  if (facadeHost.circPlayground) throw new Error('A different circ playground tool registry is already installed.');

  const controller = createPlaygroundController({ read: options.readStatus } satisfies StatusReader);
  const registry = new AgentToolRegistry(options.pageId ?? pageId(), [
    { descriptor: statusDescriptor, handler: statusHandler(controller) },
  ]);
  const native = options.native ?? new WebMcpAdapter(registry, detectNativeRegistrar());
  const api = Object.freeze({
    apiVersion: 1 as const,
    pageId: registry.pageId,
    listTools: () => registry.listTools(),
    callTool: (name: string, input: unknown) => registry.callTool(name, input),
  });

  let disposed = false;
  const onPageHide = (event: PageTransitionEvent) => {
    if (event.persisted) {
      registry.suspend();
      void native.suspend();
    } else {
      void dispose();
    }
  };
  const onPageShow = (event: PageTransitionEvent) => {
    if (!event.persisted || disposed) return;
    registry.resume();
    void native.resume();
  };
  async function dispose(): Promise<void> {
    if (disposed) return;
    disposed = true;
    registry.dispose();
    controller.dispose();
    window.removeEventListener('pagehide', onPageHide);
    window.removeEventListener('pageshow', onPageShow);
    if (facadeHost.circPlayground === api) delete facadeHost.circPlayground;
    installs.delete(el);
    await native.dispose();
  }

  const installation: PageApiInstallation = { api, registry, native, dispose };
  installs.set(el, installation);
  facadeHost.circPlayground = api;
  window.addEventListener('pagehide', onPageHide);
  window.addEventListener('pageshow', onPageShow);
  void native.start();
  return installation;
}
