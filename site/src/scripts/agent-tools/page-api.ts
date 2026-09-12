import type { PlaygroundPageApi, PlaygroundStatus, StatusReader } from '../playground-contract.ts';
import { createPlaygroundController } from '../playground-controller.ts';
import { AgentToolRegistry } from './registry.ts';
import { statusDescriptor, statusHandler } from './status.ts';
import { listProjectsDescriptor, readFileDescriptor, readProjectDescriptor, workspaceHandlers } from './workspace.ts';
import { WebMcpAdapter, detectNativeRegistrar } from '../webmcp-adapter.ts';
import type { WorkspaceSnapshot } from '../playground-reads.ts';
import type { OperationStore } from '../playground-operations.ts';
import { waitForOperationDescriptor, waitForOperationHandler } from './operations.ts';
import { helpDescriptor, helpHandler, type HelpToolOptions } from './help.ts';
import { authoringHandlers, createProjectDescriptor, openProjectDescriptor, selectEntryDescriptor, setCompileSettingsDescriptor, updateProjectDescriptor } from './authoring.ts';
import { compileDescriptor, compilerHandlers, diagnosticsDescriptor } from './compiler.ts';
import type { AuthoringPort } from '../playground-controller.ts';
import type { SimulationPort } from '../playground-controller.ts';
import { getSimulationDescriptor, prepareSimulationDescriptor, driveDescriptor, resetDescriptor, readMemoryDescriptor, updateMemoryDescriptor, setMemoryPreloadDescriptor, simulationHandlers } from './simulation.ts';
import { getVerificationDescriptor, runVerificationDescriptor, verificationHandlers } from './verification.ts';
import { getSchematicDescriptor, getTopologyDescriptor, getTruthTableDescriptor, inspectionHandlers, requestSchematicDescriptor, requestTruthTableDescriptor } from './inspection.ts';
import { highlightDescriptor, setViewDescriptor, setWorkbenchSettingsDescriptor, workbenchHandlers } from './workbench.ts';
import { createShareLinkDescriptor, downloadArtifactDescriptor, downloadMemoryDescriptor, exportHandlers, exportSourceDescriptor, getTranscriptDescriptor } from './exports.ts';
import type { HandoffPort, InspectionPort, WorkbenchPort } from '../playground-controller.ts';

export interface PageApiInstallation {
  readonly api: PlaygroundPageApi;
  readonly registry: AgentToolRegistry;
  readonly native: WebMcpAdapter;
  dispose(): Promise<void>;
}

export interface InstallPageApiOptions {
  readStatus: () => PlaygroundStatus;
  readWorkspace?: () => WorkspaceSnapshot | null;
  pageId?: string;
  native?: WebMcpAdapter;
  operations?: OperationStore;
  help?: HelpToolOptions;
  authoring?: AuthoringPort;
  simulation?: SimulationPort;
  inspection?: InspectionPort;
  workbench?: WorkbenchPort;
  handoff?: HandoffPort;
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

  const controller = createPlaygroundController({ read: options.readStatus } satisfies StatusReader, options.readWorkspace, options.operations, options.authoring, options.simulation, options.inspection, options.workbench, options.handoff);
  const workspace = workspaceHandlers(controller);
  const authoring = authoringHandlers(controller);
  const compiler = compilerHandlers(controller);
  const simulation = simulationHandlers(controller);
  const verification = verificationHandlers(controller);
  const inspection = inspectionHandlers(controller);
  const workbench = workbenchHandlers(controller);
  const exports = exportHandlers(controller);
  const registry = new AgentToolRegistry(options.pageId ?? pageId(), [
    { descriptor: statusDescriptor, handler: statusHandler(controller) },
    { descriptor: listProjectsDescriptor, handler: (input) => workspace.listProjects(input as { cursor?: string; limit?: number }) },
    { descriptor: readProjectDescriptor, handler: (input) => workspace.readProject(input as { projectId?: string; expectedRevision?: string; cursor?: string; limit?: number }) },
    { descriptor: readFileDescriptor, handler: (input) => workspace.readFile(input as { projectId?: string; name: string; expectedSourceRevision?: string; offset?: number; maxCodeUnits?: number }) },
    { descriptor: waitForOperationDescriptor, handler: waitForOperationHandler(controller) },
    { descriptor: createProjectDescriptor, handler: authoring.createProject },
    { descriptor: openProjectDescriptor, handler: authoring.openProject },
    { descriptor: updateProjectDescriptor, handler: authoring.updateProject },
    { descriptor: selectEntryDescriptor, handler: authoring.selectEntry },
    { descriptor: setCompileSettingsDescriptor, handler: authoring.setCompileSettings },
    { descriptor: compileDescriptor, handler: compiler.compile },
    { descriptor: diagnosticsDescriptor, handler: compiler.diagnostics },
    { descriptor: getSimulationDescriptor, handler: simulation.get },
    { descriptor: prepareSimulationDescriptor, handler: simulation.prepare },
    { descriptor: driveDescriptor, handler: simulation.drive },
    { descriptor: resetDescriptor, handler: simulation.reset },
    { descriptor: readMemoryDescriptor, handler: simulation.readMemory },
    { descriptor: updateMemoryDescriptor, handler: simulation.updateMemory },
    { descriptor: setMemoryPreloadDescriptor, handler: simulation.setMemoryPreload },
    { descriptor: runVerificationDescriptor, handler: verification.run },
    { descriptor: getVerificationDescriptor, handler: verification.get },
    { descriptor: requestSchematicDescriptor, handler: inspection.requestSchematic },
    { descriptor: getSchematicDescriptor, handler: inspection.getSchematic },
    { descriptor: getTopologyDescriptor, handler: inspection.getTopology },
    { descriptor: requestTruthTableDescriptor, handler: inspection.requestTruth },
    { descriptor: getTruthTableDescriptor, handler: inspection.getTruth },
    { descriptor: setWorkbenchSettingsDescriptor, handler: workbench.settings },
    { descriptor: setViewDescriptor, handler: workbench.view },
    { descriptor: highlightDescriptor, handler: workbench.highlight },
    { descriptor: exportSourceDescriptor, handler: exports.source },
    { descriptor: createShareLinkDescriptor, handler: exports.share },
    { descriptor: downloadArtifactDescriptor, handler: exports.artifact },
    { descriptor: downloadMemoryDescriptor, handler: exports.memory },
    { descriptor: getTranscriptDescriptor, handler: exports.transcript },
    ...(options.help ? [{ descriptor: helpDescriptor, handler: helpHandler(options.help) }] : []),
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
      controller.cancelWaits('PAGE_SUSPENDED');
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
