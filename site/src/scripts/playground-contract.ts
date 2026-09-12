export const AGENT_API_VERSION = 1 as const;
export const MAX_TOOL_RESULT_BYTES = 32 * 1024;
export const MAX_AGENT_INPUT_BYTES = 128 * 1024;

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
  | 'INPUT_TOO_LARGE'
  | 'PROJECT_NOT_ACTIVE'
  | 'TARGET_CONFLICT'
  | 'OPTIONS_CONFLICT'
  | 'FILE_CONFLICT'
  | 'SOURCE_TOO_LARGE'
  | 'TOO_MANY_FILES'
  | 'UNSAVED_CHANGES'
  | 'DIAGNOSTICS_NOT_READY'
  | 'DIAGNOSTICS_UNAVAILABLE'
  | 'DIAGNOSTICS_EXPIRED'
  | 'ARTIFACT_CONFLICT'
  | 'SESSION_NOT_READY'
  | 'SESSION_CONFLICT'
  | 'LIVE_STATE_CONFLICT'
  | 'IMAGE_CONFLICT'
  | 'SIMULATION_REFUSED'
  | 'SIMULATION_FAILED'
  | 'MEMORY_NOT_ROOT'
  | 'PRELOAD_CONFLICT'
  | 'VERIFICATION_INVALID'
  | 'VERIFICATION_NOT_READY'
  | 'VERIFICATION_EXPIRED'
  | 'VERIFICATION_UNAVAILABLE'
  | 'INSPECTION_NOT_READY'
  | 'INSPECTION_UNAVAILABLE'
  | 'INSPECTION_EXPIRED'
  | 'TOPOLOGY_UNAVAILABLE'
  | 'TRUTH_TOO_LARGE'
  | 'TRUTH_NEEDS_SESSION'
  | 'WORKBENCH_CONFLICT'
  | 'HIGHLIGHT_NOT_FOUND'
  | 'EXPORT_UNAVAILABLE'
  | 'SHARE_TOO_LARGE'
  | 'SHARE_CODEC_UNAVAILABLE'
  | 'DOWNLOAD_FAILED'
  | 'CURSOR_CONFLICT'
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
  | 'session_reset'
  | 'verification';

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
export interface CompileSettingsStatus { revision: Revision; warningsAsErrors: boolean; }
export type PersistenceNotice =
  | { kind: 'evicted'; cause: 'project_cap' | 'quota'; count: number; reportedProjects: { id: string; name: string }[]; omittedCount: number }
  | { kind: 'images_skipped'; ownerCount: number }
  | { kind: 'disabled'; reason: 'quota' | 'unavailable' };
export type PersistenceReceipt =
  | { state: 'unchanged'; enabled: boolean; persistedActive: null; notices: [] }
  | { state: 'saved'; enabled: true; persistedActive: { projectId: string; projectRevision: Revision; sourceRevision: Revision; sourceStored: 'inline' | 'catalogue' }; notices: Exclude<PersistenceNotice, { kind: 'disabled' }>[] }
  | { state: 'memory_only'; enabled: false; persistedActive: null; notices: [Extract<PersistenceNotice, { kind: 'disabled' }>, ...PersistenceNotice[]] };
export type AuthoringWarning = { kind: 'imports_not_rewritten'; oldName: string; newName: string };
export interface WorkspaceChangeResult {
  disposition: 'created' | 'opened' | 'updated' | 'entry_selected' | 'settings_updated' | 'unchanged';
  workspaceRevision: Revision; project: ProjectSummary; target: TargetRef; compileSettings: CompileSettingsStatus; entryFile: string;
  forkedFromProjectId: string | null; previousProjectId: string | null; warnings: AuthoringWarning[];
  operationIds: { analyze: OperationId | null; compile: OperationId | null }; persistence: PersistenceReceipt;
}
export type TextEdit = { from: number; to: number; text: string };
export type FileMutation =
  | { kind: 'edit'; name: string; edits: TextEdit[] }
  | { kind: 'create'; name: string; body?: string; before?: string | null }
  | { kind: 'rename'; name: string; newName: string }
  | { kind: 'delete'; name: string };
export interface CompileTicket { target: TargetRef; optionsRevision: Revision; analysis: { operationId: OperationId; disposition: 'started' | 'joined' | 'already_current' }; compile: { operationId: OperationId; disposition: 'started' | 'joined' | 'already_current' }; artifactId: ArtifactId | null; }
export type NativeDiagnosticRange = { lineBase: 1; columnBase: 1; columnEncoding: 'utf8-bytes'; endExclusive: true; startLine: number; startColumn: number; endLine: number; endColumn: number };
export type SourceDiagnosticRange = { lineBase: 1; columnBase: 1; columnEncoding: 'utf16'; offsetBase: 0; endExclusive: true; startLine: number; startColumn: number; endLine: number; endColumn: number; startOffset: number; endOffset: number };
export interface DiagnosticLocation { fileId: number; path: string | null; fileName: string | null; sourceAvailable: boolean; currentlyEditable: boolean; nativeRange: NativeDiagnosticRange; sourceRange: SourceDiagnosticRange | null; }
export interface AgentDiagnostic { severity: 'error' | 'warning'; code: string; message: string; location: DiagnosticLocation; related: { message: string; location: DiagnosticLocation }[]; }
export interface DiagnosticCompilerIdentity { version: string; revision: string; parser: string; parserRuntimeSha256: string; grammarSha256: string; topologyVersion: number; fullVersion: number; }
export interface DiagnosticPage { requestedOperationId: OperationId; producerOperationId: OperationId; diagnosticSetId: string; observationRevision: Revision; requestedInputs: WorkInputs; producerInputs: WorkInputs; compiler: DiagnosticCompilerIdentity; counts: DiagnosticCounts; diagnostics: AgentDiagnostic[]; nextCursor: string | null; }
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

export const MAX_SIM_ASSIGNMENTS = 64;
export const MAX_SIM_QUERIES = 128;
export const DEFAULT_MEMORY_READ_WORDS = 64;
export const MAX_MEMORY_READ_WORDS = 256;
export const MAX_VERIFICATION_CASES = 128;
export const MAX_VERIFICATION_STEPS = 512;
export const MAX_VERIFICATION_ACTIONS = 2048;
export const MAX_VERIFICATION_ASSERTIONS = 2048;
export const MAX_VERIFICATION_IMAGES = 16;
export const DEFAULT_VERIFICATION_TIMEOUT_MS = 5_000;
export const MAX_VERIFICATION_TIMEOUT_MS = 10_000;
export const DEFAULT_VERIFICATION_PAGE_LIMIT = 20;
export const MAX_VERIFICATION_PAGE_LIMIT = 100;

export interface SignalValue { value: string; defined: string; width: number; }
export interface SimulationPin { name: string; kind: 'in' | 'out'; width: number; state: SignalValue; }
export interface RootMemory {
  name: string; kind: 'rom' | 'ram'; width: number; addressWidth: number; words: number;
  liveAccess: 'root'; sourceOwner: { projectId: string; file: string; declaration: string } | null;
}
export interface SimulationRef {
  target: TargetRef; artifactId: ArtifactId; sessionId: SessionId; liveStateRevision: Revision;
  imageRevision: Revision; initialization: 'page_boot_low' | 'reset_floating'; preloadState: SessionStatus['preloadState'];
}
export interface SimulationSnapshot { observationRevision: Revision; status: SessionStatus; simulation: SimulationRef | null; pins: SimulationPin[]; memories: RootMemory[]; }
export interface SimulationOperationTicket { operationId: OperationId; kind: 'session_build' | 'session_reset'; disposition: 'started' | 'joined' | 'already_current'; inputs: WorkInputs; sessionId: SessionId | null; }
export interface DriveInput {
  projectId: string; expectedTargetEpoch: Revision; expectedArtifactId: ArtifactId; expectedSessionId: SessionId;
  expectedLiveStateRevision: Revision; assignments: { pin: string; value: string; defined?: string }[]; queries?: string[];
}
export interface DriveResult {
  simulation: SimulationRef; disposition: 'driven' | 'unchanged'; assignments: { pin: string; state: SignalValue }[];
  values: SimulationPin[]; consoleRecord: { recorded: true; lines: number };
}
export type LiveMemoryAction = { kind: 'poke'; address: string; value: string; defined?: string } | { kind: 'clear' } | { kind: 'load'; hex: string };
export interface MemoryCell { address: string; state: SignalValue; }
export interface MemoryPage { simulation: SimulationRef; memory: RootMemory; start: string; cells: MemoryCell[]; nextStart: string | null; }
export interface UpdateMemoryInput {
  projectId: string; expectedTargetEpoch: Revision; expectedArtifactId: ArtifactId; expectedSessionId: SessionId;
  expectedLiveStateRevision: Revision; memory: string; action: LiveMemoryAction;
}
export interface UpdateMemoryResult { simulation: SimulationRef; memory: RootMemory; action: 'poke' | 'clear' | 'load'; wordsLoaded: number | null; consoleRecord: { recorded: true; lines: number }; }
export interface SetMemoryPreloadInput {
  projectId: string; expectedSourceRevision: Revision; expectedImageRevision: Revision; expectedTargetEpoch: Revision;
  file: string; declaration: string; hex: string | null;
}
export interface PreloadApplicationSummary {
  state: 'not_running' | 'not_current' | 'applied' | 'partial' | 'failed'; rootApplied: boolean;
  importedInstancesApplied: number; failedInstances: number; reportedFailures: { instance: string; message: string }[];
  omittedFailureCount: number; sessionId: SessionId | null; liveStateRevision: Revision | null;
}
export interface SetMemoryPreloadResult extends WorkspaceChangeResult {
  imageRevision: Revision; owner: { projectId: string; file: string; declaration: string };
  image: { present: boolean; hex: string | null; words: number | null }; liveApplication: PreloadApplicationSummary;
}
export interface VerificationImage { memory: string; hex: string; }
export type VerificationAction =
  | { kind: 'drive'; pin: string; value: string; defined?: string }
  | { kind: 'poke'; memory: string; address: string; value: string; defined?: string }
  | { kind: 'clear'; memory: string }
  | { kind: 'load'; memory: string; hex: string }
  | { kind: 'reset' };
export type VerificationExpectation =
  | { kind: 'pin'; name: string; value: string; defined?: string }
  | { kind: 'memory'; name: string; address: string; value: string; defined?: string };
export interface VerificationStep { id: string; actions: VerificationAction[]; expect: VerificationExpectation[]; }
export interface VerificationCase { id: string; initialization: 'floating' | 'low'; sourcePreloads: 'current' | 'none'; images?: VerificationImage[]; steps: VerificationStep[]; }
export interface RunVerificationInput {
  projectId: string; expectedSourceRevision: Revision; expectedTargetEpoch: Revision; expectedArtifactId: ArtifactId;
  expectedImageRevision: Revision; timeoutMs?: number; stopOnFailure?: boolean; cases: VerificationCase[];
}
export interface VerificationTicket { operationId: OperationId; disposition: 'started' | 'joined' | 'already_complete'; inputs: WorkInputs; caseCount: number; stepCount: number; assertionCount: number; }
export interface VerificationAssertionResult {
  expectationIndex: number; expected: { kind: 'pin' | 'memory'; name: string; address: string | null; state: SignalValue };
  actual: { kind: 'pin' | 'memory'; name: string; address: string | null; state: SignalValue } | null;
  passed: boolean; error: { simCode: string; arg: string } | null;
}
export interface VerificationStepResult { caseId: string; stepId: string; state: 'passed' | 'failed' | 'error' | 'not_run'; actionsCompleted: number; assertions: VerificationAssertionResult[]; }
export interface VerificationSummary { operationId: OperationId; state: 'passed' | 'failed' | 'error' | 'timed_out' | 'cancelled'; cases: number; steps: number; assertions: number; passedAssertions: number; failedAssertions: number; notRunSteps: number; elapsedMs: number; }
export interface VerificationPage {
  operationId: OperationId; resultId: string; observationRevision: Revision; inputs: WorkInputs;
  artifactValidation: { operationId: OperationId; inputs: WorkInputs; counts: DiagnosticCounts | null } | null;
  imageRevision: Revision; summary: VerificationSummary; steps: VerificationStepResult[]; nextCursor: string | null;
}

export const MAX_TRUTH_COMPUTE_ROWS = 4096;
export const MAX_TRUTH_RESULT_BYTES = 1024 * 1024;
export const MAX_RETAINED_TRUTH_RESULTS = 8;
export const MAX_RETAINED_TRUTH_BYTES = 2 * 1024 * 1024;
export const DEFAULT_TRUTH_PAGE_ROWS = 32;
export const MAX_TRUTH_PAGE_ROWS = 128;
export const MAX_SCHEMATIC_RESULT_BYTES = 1024 * 1024;
export const MAX_RETAINED_SCHEMATICS = 8;
export const DEFAULT_TEXT_PAGE_CODE_UNITS = 12 * 1024;
export const MAX_TEXT_PAGE_CODE_UNITS = 24 * 1024;
export const MAX_TOPOLOGY_SECTION_BYTES = 4 * 1024 * 1024;
export const MAX_TOPOLOGY_COMPONENTS = 32768;
export const MAX_TOPOLOGY_CONNECTIONS = 65536;
export const MAX_TOPOLOGY_ORIGIN_FRAMES = 131072;
export const DEFAULT_TOPOLOGY_PAGE_ITEMS = 50;
export const MAX_TOPOLOGY_PAGE_ITEMS = 200;

export interface InspectionTicket { operationId: OperationId; disposition: 'started' | 'joined' | 'already_current'; inputs: WorkInputs; }
export interface SchematicPage {
  operationId: OperationId; inputs: WorkInputs; compiler: DiagnosticCompilerIdentity;
  settings: { expandMacros: boolean; expandDisplay: boolean; color: 'never' };
  dimensions: { rows: number; columns: number; codeUnits: number; utf8Bytes: number };
  text: string; nextCursor: string | null;
}
export interface TopologyOrigin { alias: string; subcircuit: string; targetFileId: number; targetFile: string | null; }
export interface TopologyComponent {
  id: number; kind: string; width: number; name: string; origins: TopologyOrigin[];
  slice: { start: number; end: number } | null; memory: { kind: 'rom' | 'ram'; addressWidth: number } | null;
}
export interface TopologyConnection { fromId: number; toId: number; port: number; portLabel: string | null; }
export interface TopologyPage {
  artifactId: ArtifactId; sourceRevision: Revision; topologyVersion: number; section: 'components' | 'connections'; scope: 'root' | 'flattened';
  totalComponents: number; totalConnections: number; components?: TopologyComponent[]; connections?: TopologyConnection[]; nextCursor: string | null;
}
export interface TruthScope {
  kind: 'exhaustive' | 'filtered'; engine: 'compiler' | 'scratch_session'; inputBits: number; enumeratedBits: number; rowCount: number; cap: number;
  heldInputs: { name: string; state: SignalValue }[]; unknownInputs: { name: string; width: number }[]; partialBusPolicy: 'whole_bus_unknown';
}
export interface TruthPage {
  operationId: OperationId; inputs: WorkInputs; compiler: DiagnosticCompilerIdentity; scope: TruthScope;
  columns: { name: string; kind: 'in' | 'out'; width: number }[];
  rows: { index: number; inputs: (string | null)[]; outputs: (string | null)[] }[]; nextCursor: string | null;
}
export type ExportOmission = 'source_images' | 'live_ram' | 'live_pin_state' | 'active_entry_selection' | 'settings' | 'transcript' | 'compiled_artifact';
export interface TextExportPage {
  exportId: string; contentType: string; text: string; nextCursor: string | null;
  provenance: { target: TargetRef; sourceRevision: Revision; sessionId: SessionId | null };
  contents: string[]; omissions: ExportOmission[];
}
export interface DownloadReceipt {
  dispatchId: string; state: 'dispatched'; filename: string; mediaType: 'application/wasm' | 'application/octet-stream'; bytes: number;
  provenance: { target: TargetRef; artifactId: ArtifactId | null; sessionId: SessionId | null; liveStateRevision: Revision | null; imageRevision: Revision | null };
  contents: string[]; omissions: ExportOmission[]; completionKnown: false;
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
  /** Current workspace snapshot revision for create/open preconditions. */
  workspaceRevision?: Revision;
  projectVersion?: ProjectVersion | null;
  currentTarget?: TargetRef | null;
  outputs?: { analysis: OutputStatus; diagnostics: OutputStatus; artifact: OutputStatus & { id: ArtifactId | null }; preview: OutputStatus; truth: OutputStatus };
  simulation?: SessionStatus;
  operationIds?: Record<OperationKind, OperationId | null>;
  compilerTransport?: { state: 'not_started' | 'starting' | 'available' | 'failed'; failure: string | null };
  configuration?: { compile: CompileSettingsStatus; workbench: { revision: Revision; previewOptionsRevision: Revision; truthOptionsRevision: Revision }; presentationRevision: Revision };
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
  createProject(input: { expectedWorkspaceRevision: Revision; expectedActiveProjectId: string | null; expectedTargetEpoch: Revision | null; name?: string; files?: { name: string; body: string }[]; entryFile?: string }): DomainResult<WorkspaceChangeResult>;
  openProject(input: { expectedWorkspaceRevision: Revision; expectedActiveProjectId: string | null; expectedTargetEpoch: Revision | null; projectId: string; expectedRevision: Revision; entryFile?: string }): DomainResult<WorkspaceChangeResult>;
  updateProject(input: { projectId: string; expectedSourceRevision: Revision; expectedTargetEpoch: Revision; operations: FileMutation[] }): DomainResult<WorkspaceChangeResult>;
  selectEntry(input: { projectId: string; expectedSourceRevision: Revision; expectedTargetEpoch: Revision; name: string }): DomainResult<WorkspaceChangeResult>;
  setCompileSettings(input: { projectId: string; expectedTargetEpoch: Revision; expectedOptionsRevision: Revision; warningsAsErrors: boolean }): DomainResult<WorkspaceChangeResult>;
  compile(input: { projectId: string; expectedSourceRevision: Revision; expectedTargetEpoch: Revision; expectedOptionsRevision: Revision }): DomainResult<CompileTicket>;
  getDiagnostics(input: { operationId: string; expectedSourceRevision?: Revision; cursor?: string; limit?: number }): DomainResult<DiagnosticPage>;
  getSimulation(input: { expectedSessionId?: SessionId; expectedLiveStateRevision?: Revision }): DomainResult<SimulationSnapshot>;
  prepareSimulation(input: { projectId: string; expectedSourceRevision: Revision; expectedTargetEpoch: Revision; expectedArtifactId: ArtifactId; expectedImageRevision: Revision }): DomainResult<SimulationOperationTicket>;
  drive(input: DriveInput): DomainResult<DriveResult>;
  reset(input: { projectId: string; expectedTargetEpoch: Revision; expectedArtifactId: ArtifactId; expectedSessionId: SessionId; expectedLiveStateRevision: Revision }): DomainResult<SimulationOperationTicket>;
  readMemory(input: { expectedArtifactId: ArtifactId; expectedSessionId: SessionId; memory: string; start?: string; count?: number }): DomainResult<MemoryPage>;
  updateMemory(input: UpdateMemoryInput): DomainResult<UpdateMemoryResult>;
  setMemoryPreload(input: SetMemoryPreloadInput): DomainResult<SetMemoryPreloadResult>;
  runVerification(input: RunVerificationInput): DomainResult<VerificationTicket>;
  getVerification(input: { operationId: OperationId; cursor?: string; limit?: number }): DomainResult<VerificationPage>;
  requestSchematic(input: { projectId: string; expectedSourceRevision: Revision; expectedTargetEpoch: Revision; expectedPreviewOptionsRevision: Revision }): DomainResult<InspectionTicket>;
  getSchematic(input: { operationId: OperationId; cursor?: string; maxCodeUnits?: number }): DomainResult<SchematicPage>;
  getTopology(input: { expectedArtifactId: ArtifactId; section: 'components' | 'connections'; scope?: 'root' | 'flattened'; cursor?: string; limit?: number }): Promise<DomainResult<TopologyPage>>;
  requestTruthTable(input: { projectId: string; expectedSourceRevision: Revision; expectedTargetEpoch: Revision; expectedTruthOptionsRevision: Revision; expectedImageRevision: Revision; expectedArtifactId?: ArtifactId; expectedSessionId?: SessionId; expectedLiveStateRevision?: Revision }): DomainResult<InspectionTicket>;
  getTruthTable(input: { operationId: OperationId; cursor?: string; limit?: number }): DomainResult<TruthPage>;
  setWorkbenchSettings(input: { projectId: string; expectedTargetEpoch: Revision; expectedWorkbenchSettingsRevision: Revision; values: { expandMacros?: boolean; expandDisplay?: boolean; valueFormat?: 'binary' | 'hex' | 'decimal'; truthTableCap?: number; editor?: { wrapLines?: boolean; fontSize?: number; tabSize?: number } } }): DomainResult<WorkspaceChangeResult>;
  setView(input: { expectedPresentationRevision: Revision; view?: 'schematic' | 'live' | 'truth'; dataOpen?: boolean }): DomainResult<{ view: 'schematic' | 'live' | 'truth'; dataOpen: boolean; presentationRevision: Revision; operationIds: Partial<Record<OperationKind, OperationId>>; persistence: PersistenceReceipt }>;
  highlight(input: { expectedTargetEpoch: Revision; expectedSourceRevision: Revision; expectedArtifactId: ArtifactId | null; declaration: { name: string; kind: string } | null }): DomainResult<{ declaration: { name: string; kind: string } | null; surfaces: { source: boolean; canvas: boolean; truth: boolean } }>;
  exportSource(input: { projectId: string; expectedSourceRevision: Revision; expectedTargetEpoch: Revision; format?: 'combined' | 'files'; cursor?: string; maxCodeUnits?: number }): DomainResult<TextExportPage>;
  createShareLink(input: { projectId: string; expectedSourceRevision: Revision; expectedTargetEpoch: Revision }): Promise<DomainResult<{ url: string; key: 'src' | 'src0'; payloadChars: number; cap: number; provenance: TextExportPage['provenance']; contents: string[]; omissions: ExportOmission[] }>>;
  downloadArtifact(input: { expectedArtifactId: ArtifactId }): DomainResult<DownloadReceipt>;
  downloadMemory(input: { source: 'live_root'; projectId: string; expectedTargetEpoch: Revision; expectedArtifactId: ArtifactId; expectedSessionId: SessionId; expectedLiveStateRevision: Revision; memory: string } | { source: 'source_preload'; projectId: string; expectedSourceRevision: Revision; expectedImageRevision: Revision; file: string; declaration: string }): DomainResult<DownloadReceipt>;
  getTranscript(input: { format: 'log' | 'script'; cursor?: string; limit?: number }): DomainResult<{ transcriptId: string; revision: Revision; truncated: boolean; lines: string[]; nextCursor: string | null; sessionId: SessionId | null }>;
}
