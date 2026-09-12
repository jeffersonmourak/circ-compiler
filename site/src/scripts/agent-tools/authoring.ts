import type { PlaygroundController, ToolDescriptor } from '../playground-contract.ts';

const revision = { type: 'string' } as const;
const bool = { type: 'boolean' } as const;

const nullableRevision = { type: 'string', nullable: true } as const;
export const createProjectDescriptor: ToolDescriptor = { name: 'circ_create_project', description: 'Create and visibly open a scratch circ project. Read status first and supply its workspace, active-project, and target revisions.', readOnly: false, inputSchema: { type: 'object', properties: { expectedWorkspaceRevision: revision, expectedActiveProjectId: nullableRevision, expectedTargetEpoch: nullableRevision, name: revision, files: { type: 'array' }, entryFile: revision }, required: ['expectedWorkspaceRevision', 'expectedActiveProjectId', 'expectedTargetEpoch'], additionalProperties: false } };
export const openProjectDescriptor: ToolDescriptor = { name: 'circ_open_project', description: 'Visibly open an existing circ project after reading its current project and workspace revisions.', readOnly: false, inputSchema: { type: 'object', properties: { expectedWorkspaceRevision: revision, expectedActiveProjectId: nullableRevision, expectedTargetEpoch: nullableRevision, projectId: revision, expectedRevision: revision, entryFile: revision }, required: ['expectedWorkspaceRevision', 'expectedActiveProjectId', 'expectedTargetEpoch', 'projectId', 'expectedRevision'], additionalProperties: false } };
export const updateProjectDescriptor: ToolDescriptor = { name: 'circ_update_project', description: 'Atomically edit, create, rename, or delete active project files against a source revision. Read project/status first.', readOnly: false, inputSchema: { type: 'object', properties: { projectId: revision, expectedSourceRevision: revision, expectedTargetEpoch: revision, operations: { type: 'array' } }, required: ['projectId', 'expectedSourceRevision', 'expectedTargetEpoch', 'operations'], additionalProperties: false } };
export const selectEntryDescriptor: ToolDescriptor = { name: 'circ_select_entry', description: 'Select the visible compilation entry without reordering files. Read status first.', readOnly: false, inputSchema: { type: 'object', properties: { projectId: revision, expectedSourceRevision: revision, expectedTargetEpoch: revision, name: revision }, required: ['projectId', 'expectedSourceRevision', 'expectedTargetEpoch', 'name'], additionalProperties: false } };
export const setCompileSettingsDescriptor: ToolDescriptor = { name: 'circ_set_compile_settings', description: 'Set warnings-as-errors for the visible project using target and compile-settings revisions from status.', readOnly: false, inputSchema: { type: 'object', properties: { projectId: revision, expectedTargetEpoch: revision, expectedOptionsRevision: revision, warningsAsErrors: bool }, required: ['projectId', 'expectedTargetEpoch', 'expectedOptionsRevision', 'warningsAsErrors'], additionalProperties: false } };

export function authoringHandlers(controller: PlaygroundController) {
  return {
    createProject: (input: Record<string, unknown>) => controller.createProject(input as Parameters<PlaygroundController['createProject']>[0]),
    openProject: (input: Record<string, unknown>) => controller.openProject(input as Parameters<PlaygroundController['openProject']>[0]),
    updateProject: (input: Record<string, unknown>) => controller.updateProject(input as Parameters<PlaygroundController['updateProject']>[0]),
    selectEntry: (input: Record<string, unknown>) => controller.selectEntry(input as Parameters<PlaygroundController['selectEntry']>[0]),
    setCompileSettings: (input: Record<string, unknown>) => controller.setCompileSettings(input as Parameters<PlaygroundController['setCompileSettings']>[0]),
  };
}
