import type { AgentError, AgentErrorCode, CompileTicket, DiagnosticPage, DomainResult, FileChunk, PlaygroundController, PlaygroundStatus, ProjectManifest, ProjectPage, StatusReader, WaitResult, WorkspaceChangeResult } from './playground-contract.ts';
import { listProjects, readFile, readProject, type ReadResult, type WorkspaceSnapshot } from './playground-reads.ts';
import { OperationStore } from './playground-operations.ts';

export class ControllerDisposedError extends Error {
  constructor() {
    super('The playground page has been disposed. Rediscover its tools after reload.');
  }
}

/** The island owns DOM, storage, and compiler scheduling. The controller only
 * gates lifecycle and exposes that single commit boundary to every tool path. */
export interface AuthoringPort {
  createProject(input: Parameters<PlaygroundController['createProject']>[0]): DomainResult<WorkspaceChangeResult>;
  openProject(input: Parameters<PlaygroundController['openProject']>[0]): DomainResult<WorkspaceChangeResult>;
  updateProject(input: Parameters<PlaygroundController['updateProject']>[0]): DomainResult<WorkspaceChangeResult>;
  selectEntry(input: Parameters<PlaygroundController['selectEntry']>[0]): DomainResult<WorkspaceChangeResult>;
  setCompileSettings(input: Parameters<PlaygroundController['setCompileSettings']>[0]): DomainResult<WorkspaceChangeResult>;
  compile(input: Parameters<PlaygroundController['compile']>[0]): DomainResult<CompileTicket>;
  getDiagnostics(input: Parameters<PlaygroundController['getDiagnostics']>[0]): DomainResult<DiagnosticPage>;
}

export type SimulationPort = Pick<PlaygroundController,
  'getSimulation' | 'prepareSimulation' | 'drive' | 'reset' | 'readMemory' | 'updateMemory' | 'setMemoryPreload' | 'runVerification' | 'getVerification'>;

function cloneStatus(status: PlaygroundStatus): PlaygroundStatus {
  return JSON.parse(JSON.stringify(status)) as PlaygroundStatus;
}

export class PlaygroundControllerImpl implements PlaygroundController {
  private disposed = false;

  private abort = new AbortController();
  private readonly abortReasons = new WeakMap<AbortSignal, 'WAIT_CANCELLED' | 'PAGE_SUSPENDED' | 'PAGE_DISPOSED'>();
  constructor(private readonly reader: StatusReader, private readonly workspace?: () => WorkspaceSnapshot | null, private readonly operations?: OperationStore, private readonly authoring?: AuthoringPort, private readonly simulation?: SimulationPort) {}

  getStatus(): PlaygroundStatus {
    if (this.disposed) throw new ControllerDisposedError();
    return cloneStatus(this.reader.read());
  }

  listProjects(input: { cursor?: string; limit?: number }): DomainResult<ProjectPage> {
    return this.readWorkspace((snapshot) => listProjects(snapshot, input));
  }

  readProject(input: { projectId?: string; expectedRevision?: string; cursor?: string; limit?: number }): DomainResult<ProjectManifest> {
    return this.readWorkspace((snapshot) => readProject(snapshot, input));
  }

  readFile(input: { projectId?: string; name: string; expectedSourceRevision?: string; offset?: number; maxCodeUnits?: number }): DomainResult<FileChunk> {
    return this.readWorkspace((snapshot) => readFile(snapshot, input));
  }

  async waitForOperation(input: { operationId: string; timeoutMs?: number }): Promise<DomainResult<WaitResult>> {
    if (this.disposed) throw new ControllerDisposedError();
    if (!this.operations) return { ok: false, error: { code: 'OPERATION_NOT_FOUND', message: 'No operations have been issued by this page.', retryable: false } };
    const timeout = input.timeoutMs ?? 5000;
    if (typeof input.operationId !== 'string' || !Number.isSafeInteger(timeout) || timeout < 0 || timeout > 30000) {
      return { ok: false, error: { code: 'INVALID_ARGUMENT', message: 'operationId and timeoutMs are invalid.', retryable: false } };
    }
    try {
      const signal = this.abort.signal;
      const result = await this.operations.wait(input.operationId, timeout, signal);
      if ('kind' in result) {
        return { ok: false, error: { code: result.kind === 'expired' ? 'OPERATION_EXPIRED' : 'OPERATION_NOT_FOUND', message: 'The operation is not available.', retryable: false } };
      }
      if (result.wait === 'cancelled') {
        const code = this.abortReasons.get(signal) ?? 'WAIT_CANCELLED';
        return { ok: false, error: { code, message: code === 'PAGE_SUSPENDED' ? 'The playground page was suspended.' : code === 'PAGE_DISPOSED' ? 'The playground page was disposed.' : 'The wait was cancelled.', retryable: false } };
      }
      return { ok: true, value: result };
    } catch (error) {
      return { ok: false, error: { code: error instanceof Error && error.message === 'WAIT_LIMIT' ? 'WAIT_LIMIT' : 'INTERNAL_ERROR', message: 'The operation wait could not complete.', retryable: false } };
    }
  }

  createProject(input: Parameters<PlaygroundController['createProject']>[0]) { return this.write('createProject', input); }
  openProject(input: Parameters<PlaygroundController['openProject']>[0]) { return this.write('openProject', input); }
  updateProject(input: Parameters<PlaygroundController['updateProject']>[0]) { return this.write('updateProject', input); }
  selectEntry(input: Parameters<PlaygroundController['selectEntry']>[0]) { return this.write('selectEntry', input); }
  setCompileSettings(input: Parameters<PlaygroundController['setCompileSettings']>[0]) { return this.write('setCompileSettings', input); }
  compile(input: Parameters<PlaygroundController['compile']>[0]) { return this.write('compile', input); }
  getDiagnostics(input: Parameters<PlaygroundController['getDiagnostics']>[0]) { return this.write('getDiagnostics', input); }
  getSimulation(input: Parameters<PlaygroundController['getSimulation']>[0]) { return this.simulate('getSimulation', input); }
  prepareSimulation(input: Parameters<PlaygroundController['prepareSimulation']>[0]) { return this.simulate('prepareSimulation', input); }
  drive(input: Parameters<PlaygroundController['drive']>[0]) { return this.simulate('drive', input); }
  reset(input: Parameters<PlaygroundController['reset']>[0]) { return this.simulate('reset', input); }
  readMemory(input: Parameters<PlaygroundController['readMemory']>[0]) { return this.simulate('readMemory', input); }
  updateMemory(input: Parameters<PlaygroundController['updateMemory']>[0]) { return this.simulate('updateMemory', input); }
  setMemoryPreload(input: Parameters<PlaygroundController['setMemoryPreload']>[0]) { return this.simulate('setMemoryPreload', input); }
  runVerification(input: Parameters<PlaygroundController['runVerification']>[0]) { return this.simulate('runVerification', input); }
  getVerification(input: Parameters<PlaygroundController['getVerification']>[0]) { return this.simulate('getVerification', input); }

  cancelWaits(reason: 'WAIT_CANCELLED' | 'PAGE_SUSPENDED' | 'PAGE_DISPOSED' = 'WAIT_CANCELLED'): void {
    this.abortReasons.set(this.abort.signal, reason);
    this.abort.abort();
    this.abort = new AbortController();
  }

  private readWorkspace<T>(read: (snapshot: WorkspaceSnapshot) => ReadResult<T>): DomainResult<T> {
    if (this.disposed) throw new ControllerDisposedError();
    const snapshot = this.workspace?.();
    if (!snapshot) return { ok: false, error: { code: 'NOT_READY', message: 'The playground has not finished restoring projects.', retryable: true } };
    const result = read(snapshot);
    if (result.ok) return result;
    return { ok: false, error: readError(result.code, result.message) };
  }

  private write<K extends keyof AuthoringPort>(method: K, input: Parameters<AuthoringPort[K]>[0]): ReturnType<AuthoringPort[K]> {
    if (this.disposed) throw new ControllerDisposedError();
    if (!this.authoring) return { ok: false, error: { code: 'NOT_READY', message: 'The playground has not finished installing authoring tools.', retryable: true } } as ReturnType<AuthoringPort[K]>;
    return this.authoring[method](input as never) as ReturnType<AuthoringPort[K]>;
  }

  private simulate<K extends keyof SimulationPort>(method: K, input: Parameters<SimulationPort[K]>[0]): ReturnType<SimulationPort[K]> {
    if (this.disposed) throw new ControllerDisposedError();
    if (!this.simulation) return { ok: false, error: { code: 'NOT_READY', message: 'The playground has not finished installing simulation tools.', retryable: true } } as ReturnType<SimulationPort[K]>;
    return this.simulation[method](input as never) as ReturnType<SimulationPort[K]>;
  }

  dispose(): void {
    this.cancelWaits('PAGE_DISPOSED');
    this.disposed = true;
  }
}

function readError(code: Extract<AgentErrorCode, 'INVALID_ARGUMENT' | 'PROJECT_NOT_FOUND' | 'FILE_NOT_FOUND' | 'REVISION_CONFLICT' | 'INVALID_RANGE'>, message: string): AgentError {
  return { code, message, retryable: false };
}

export function createPlaygroundController(reader: StatusReader, workspace?: () => WorkspaceSnapshot | null, operations?: OperationStore, authoring?: AuthoringPort, simulation?: SimulationPort): PlaygroundController {
  return new PlaygroundControllerImpl(reader, workspace, operations, authoring, simulation);
}
