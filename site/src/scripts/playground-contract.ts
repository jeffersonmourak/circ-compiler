export const AGENT_API_VERSION = 1 as const;
export const MAX_TOOL_RESULT_BYTES = 32 * 1024;

export type AgentErrorCode =
  | 'UNKNOWN_TOOL'
  | 'INVALID_ARGUMENT'
  | 'PAGE_SUSPENDED'
  | 'PAGE_DISPOSED'
  | 'RESULT_TOO_LARGE'
  | 'NOT_READY'
  | 'PROJECT_NOT_FOUND'
  | 'FILE_NOT_FOUND'
  | 'REVISION_CONFLICT'
  | 'INVALID_RANGE'
  | 'OPERATION_NOT_FOUND'
  | 'OPERATION_EXPIRED'
  | 'WAIT_LIMIT'
  | 'WAIT_CANCELLED'
  | 'HELP_UNAVAILABLE'
  | 'HELP_INVALID_CORPUS'
  | 'HELP_CORPUS_CHANGED'
  | 'HELP_NOT_FOUND'
  | 'HELP_REMOVED'
  | 'HELP_CANCELLED'
  | 'HELP_BUSY'
  | 'INTERNAL_ERROR';

export interface AgentError {
  code: AgentErrorCode;
  message: string;
  retryable: boolean;
  details?: Record<string, string>;
}

export type Revision = string;
export type OperationId = string;
export type ArtifactId = string;
export type SessionId = string;

export interface ProjectVersion {
  projectId: string;
  revision: Revision;
  sourceRevision: Revision;
  imageRevision: Revision;
}

export interface TargetRef {
  projectId: string;
  sourceRevision: Revision;
  entryFile: string;
  targetEpoch: Revision;
}

export type OperationKind =
  | 'analyze'
  | 'compile'
  | 'preview'
  | 'truth_table'
  | 'session_build'
  | 'session_reset';

export interface WorkInputs {
  target: TargetRef;
  optionsRevision: Revision;
  imageRevision: Revision | null;
  artifactId: ArtifactId | null;
  liveStateRevision: Revision | null;
}

export type OperationState =
  | 'queued'
  | 'running'
  | 'succeeded'
  | 'diagnostics'
  | 'refused'
  | 'failed'
  | 'superseded';

export interface DiagnosticCounts { errors: number; warnings: number; }

export interface OperationSummary {
  id: OperationId;
  kind: OperationKind;
  inputs: WorkInputs;
  state: OperationState;
  createdAt: number;
  startedAt: number | null;
  finishedAt: number | null;
  counts: DiagnosticCounts | null;
  failure: { kind: 'transport' | 'bad_request' | 'oom' | 'internal' | 'runtime'; message: string; libraryStatus: number | null } | null;
  refusal: { message: string; libraryStatus: number | null } | null;
  supersededBy: OperationId | null;
  supersededReason: 'new_inputs' | 'new_request' | 'target_changed' | null;
  artifactId: ArtifactId | null;
  sessionId: SessionId | null;
  truthScope: 'exhaustive' | 'filtered' | null;
  truthPath: 'compiler' | 'scratch' | null;
}

export interface ProjectSummary {
  id: string; name: string; kind: 'example' | 'tour' | 'scratch'; active: boolean;
  version: ProjectVersion; fileCount: number;
}

export interface ProjectManifest {
  project: ProjectSummary; sourceOrigin: 'active_buffer' | 'scratch_record' | 'catalogue';
  defaultEntryFile: string; selectedEntryFile: string | null;
  files: { name: string; utf16Length: number; utf8Bytes: number; lineCount: number }[];
  nextCursor: string | null;
}

export interface FileChunk {
  projectId: string; sourceRevision: Revision; name: string; encoding: 'utf16'; offset: number;
  endOffset: number; totalCodeUnits: number; text: string; nextOffset: number | null; eof: boolean;
}

export interface WaitResult { wait: 'terminal' | 'timed_out'; operation: OperationSummary; }
export type Freshness = 'absent' | 'current' | 'stale';
export interface OutputStatus {
  freshness: Freshness;
  provenance: { operationId: OperationId; inputs: WorkInputs; counts: DiagnosticCounts | null } | null;
}
export interface SessionStatus {
  state: 'absent' | 'building' | 'ready' | 'resetting' | 'failed';
  id: SessionId | null; artifactId: ArtifactId | null; liveStateRevision: Revision | null; imageRevision: Revision | null;
  matchesCurrentTarget: boolean; matchesCurrentImages: boolean;
  preloadState: 'none' | 'applied' | 'partial' | 'failed' | 'unknown'; operationId: OperationId | null;
  preload: { applied: number; errors: number };
}

export type DomainResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: AgentError };

export interface ProjectPage {
  workspaceRevision: Revision;
  projects: ProjectSummary[];
  nextCursor: string | null;
}

export interface ObservationMethods {
  listProjects(input: { cursor?: string; limit?: number }): DomainResult<ProjectPage>;
  readProject(input: { projectId?: string; expectedRevision?: string; cursor?: string; limit?: number }): DomainResult<ProjectManifest>;
  readFile(input: { projectId?: string; name: string; expectedSourceRevision?: string; offset?: number; maxCodeUnits?: number }): DomainResult<FileChunk>;
  waitForOperation(input: { operationId: string; timeoutMs?: number }): Promise<DomainResult<WaitResult>>;
}

export type ToolResult<T> = {
  apiVersion: 1;
  pageId: string;
} & ({ ok: true; data: T } | { ok: false; error: AgentError });

export interface ToolDescriptor {
  name: string;
  description: string;
  inputSchema: {
    type: 'object';
    properties: Record<string, unknown>;
    required: string[];
    additionalProperties: false;
  };
  readOnly: boolean;
}

export interface ToolCatalogue {
  apiVersion: 1;
  pageId: string;
  tools: ToolDescriptor[];
}

export interface PlaygroundPageApi {
  readonly apiVersion: 1;
  readonly pageId: string;
  listTools(): Promise<ToolResult<ToolCatalogue>>;
  callTool(name: string, input: unknown): Promise<ToolResult<unknown>>;
}

export type NativeConnectionState =
  | 'not-configured'
  | 'checking'
  | 'unsupported'
  | 'registering'
  | 'registered'
  | 'failed'
  | 'suspended';

export interface PlaygroundStatus {
  lifecycle: 'initializing' | 'ready' | 'failed';
  bootstrapError: string | null;
  project: { id: string; name: string; entryFile: string; fileCount: number } | null;
  view: 'schematic' | 'live' | 'truth';
  compiler: {
    ready: boolean;
    loading: boolean;
    identity: {
      version: string;
      revision: string;
      topologyVersion: number;
      fullVersion: number;
      grammarSha256: string;
    } | null;
    simulationCompatible: boolean | null;
  };
  reportedPipeline: {
    kind: 'idle' | 'loading' | 'compiling' | 'live' | 'error';
    analyzing: boolean;
    building: boolean;
    analyzePending: boolean;
    buildPending: boolean;
    errors: number;
    warnings: number;
    stale: boolean;
    failure: string | null;
  };
  artifact: { present: boolean; bytes: number | null };
  session: { present: boolean };
  provenance: ({
    tracking: 'untracked';
    sourceRevision: string | null;
    buildRevision: string | null;
    sessionId: string | null;
  } | {
    tracking: 'tracked';
    sourceRevision: string | null;
    buildRevision: string | null;
    sessionId: string | null;
  });
  observationRevision?: Revision;
  projectVersion?: ProjectVersion | null;
  currentTarget?: TargetRef | null;
  outputs?: { analysis: OutputStatus; diagnostics: OutputStatus; artifact: OutputStatus & { id: ArtifactId | null }; preview: OutputStatus; truth: OutputStatus };
  simulation?: SessionStatus;
  operationIds?: Record<OperationKind, OperationId | null>;
  compilerTransport?: { state: 'not_started' | 'starting' | 'available' | 'failed'; failure: string | null };
  persistence: { enabled: boolean };
  agentAccess: {
    pageRegistry: 'available';
    native: { state: NativeConnectionState; apiVariant: string | null; reason: string | null };
  };
}

export interface StatusReader {
  read(): PlaygroundStatus;
}

export interface PlaygroundController extends ObservationMethods {
  getStatus(): PlaygroundStatus;
  cancelWaits(reason?: 'WAIT_CANCELLED' | 'PAGE_SUSPENDED' | 'PAGE_DISPOSED'): void;
  dispose(): void;
}
