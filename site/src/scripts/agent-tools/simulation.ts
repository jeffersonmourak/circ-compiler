import type { PlaygroundController, ToolDescriptor } from '../playground-contract.ts';

const string = { type: 'string' } as const;
const number = { type: 'number' } as const;
const assignment = {
  type: 'object',
  properties: { pin: string, value: string, defined: string },
  required: ['pin', 'value'],
  additionalProperties: false,
} as const;
const liveMemoryAction = {
  oneOf: [
    { type: 'object', properties: { kind: { type: 'string', const: 'poke' }, address: string, value: string, defined: string }, required: ['kind', 'address', 'value'], additionalProperties: false },
    { type: 'object', properties: { kind: { type: 'string', const: 'clear' } }, required: ['kind'], additionalProperties: false },
    { type: 'object', properties: { kind: { type: 'string', const: 'load' }, hex: string }, required: ['kind', 'hex'], additionalProperties: false },
  ],
} as const;
export const getSimulationDescriptor: ToolDescriptor = { name: 'circ_get_simulation', description: 'Observe the existing live session only. This never prepares a runtime.', readOnly: true, inputSchema: { type: 'object', properties: { expectedSessionId: string, expectedLiveStateRevision: string }, required: [], additionalProperties: false } };
export const prepareSimulationDescriptor: ToolDescriptor = { name: 'circ_prepare_simulation', description: 'Explicitly start, join, or reuse the current artifact simulation session.', readOnly: false, inputSchema: { type: 'object', properties: { projectId: string, expectedSourceRevision: string, expectedTargetEpoch: string, expectedArtifactId: string, expectedImageRevision: string }, required: ['projectId', 'expectedSourceRevision', 'expectedTargetEpoch', 'expectedArtifactId', 'expectedImageRevision'], additionalProperties: false } };
export const driveDescriptor: ToolDescriptor = { name: 'circ_drive', description: 'Drive ordered root input assignments in the ready live session, then read requested pins.', readOnly: false, inputSchema: { type: 'object', properties: { projectId: string, expectedTargetEpoch: string, expectedArtifactId: string, expectedSessionId: string, expectedLiveStateRevision: string, assignments: { type: 'array', minItems: 0, maxItems: 64, items: assignment }, queries: { type: 'array', minItems: 0, maxItems: 128, items: string } }, required: ['projectId', 'expectedTargetEpoch', 'expectedArtifactId', 'expectedSessionId', 'expectedLiveStateRevision', 'assignments'], additionalProperties: false } };
export const resetDescriptor: ToolDescriptor = { name: 'circ_reset', description: 'Reset the exact live session. Wait for the returned operation before observing its new identity.', readOnly: false, inputSchema: { type: 'object', properties: { projectId: string, expectedTargetEpoch: string, expectedArtifactId: string, expectedSessionId: string, expectedLiveStateRevision: string }, required: ['projectId', 'expectedTargetEpoch', 'expectedArtifactId', 'expectedSessionId', 'expectedLiveStateRevision'], additionalProperties: false } };
export const readMemoryDescriptor: ToolDescriptor = { name: 'circ_read_memory', description: 'Read one bounded page of a ready root ROM or RAM without changing the memory panel.', readOnly: true, inputSchema: { type: 'object', properties: { expectedArtifactId: string, expectedSessionId: string, memory: string, start: string, count: number }, required: ['expectedArtifactId', 'expectedSessionId', 'memory'], additionalProperties: false } };
export const updateMemoryDescriptor: ToolDescriptor = { name: 'circ_update_memory', description: 'Poke, clear, or load one root live memory with exact session and live-state preconditions.', readOnly: false, inputSchema: { type: 'object', properties: { projectId: string, expectedTargetEpoch: string, expectedArtifactId: string, expectedSessionId: string, expectedLiveStateRevision: string, memory: string, action: liveMemoryAction }, required: ['projectId', 'expectedTargetEpoch', 'expectedArtifactId', 'expectedSessionId', 'expectedLiveStateRevision', 'memory', 'action'], additionalProperties: false } };
export const setMemoryPreloadDescriptor: ToolDescriptor = { name: 'circ_set_memory_preload', description: 'Persist or remove one source-owned ROM preload; compatible current sessions are updated in place.', readOnly: false, inputSchema: { type: 'object', properties: { projectId: string, expectedSourceRevision: string, expectedImageRevision: string, expectedTargetEpoch: string, file: string, declaration: string, hex: { type: 'string', nullable: true } }, required: ['projectId', 'expectedSourceRevision', 'expectedImageRevision', 'expectedTargetEpoch', 'file', 'declaration', 'hex'], additionalProperties: false } };

export function simulationHandlers(controller: PlaygroundController) {
  return {
    get: (input: Record<string, unknown>) => controller.getSimulation(input as Parameters<PlaygroundController['getSimulation']>[0]),
    prepare: (input: Record<string, unknown>) => controller.prepareSimulation(input as Parameters<PlaygroundController['prepareSimulation']>[0]),
    drive: (input: Record<string, unknown>) => controller.drive(input as unknown as Parameters<PlaygroundController['drive']>[0]),
    reset: (input: Record<string, unknown>) => controller.reset(input as Parameters<PlaygroundController['reset']>[0]),
    readMemory: (input: Record<string, unknown>) => controller.readMemory(input as Parameters<PlaygroundController['readMemory']>[0]),
    updateMemory: (input: Record<string, unknown>) => controller.updateMemory(input as unknown as Parameters<PlaygroundController['updateMemory']>[0]),
    setMemoryPreload: (input: Record<string, unknown>) => controller.setMemoryPreload(input as unknown as Parameters<PlaygroundController['setMemoryPreload']>[0]),
  };
}
