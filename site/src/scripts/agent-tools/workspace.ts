import type { PlaygroundController, ToolDescriptor } from '../playground-contract.ts';

const pageSchema = {
  type: 'object' as const,
  properties: { cursor: { type: 'string' }, limit: { type: 'number' } },
  required: [],
  additionalProperties: false as const,
};

export const listProjectsDescriptor: ToolDescriptor = {
  name: 'circ_list_projects',
  description: 'List readable circ playground projects without selecting a project or compiling.',
  inputSchema: pageSchema,
  readOnly: true,
};

export const readProjectDescriptor: ToolDescriptor = {
  name: 'circ_read_project',
  description: 'Read a project file manifest without selecting a project or compiling.',
  inputSchema: {
    type: 'object',
    properties: { projectId: { type: 'string' }, expectedRevision: { type: 'string' }, cursor: { type: 'string' }, limit: { type: 'number' } },
    required: [], additionalProperties: false,
  },
  readOnly: true,
};

export const readFileDescriptor: ToolDescriptor = {
  name: 'circ_read_file',
  description: 'Read an exact bounded UTF-16 source chunk without selecting a file or compiling.',
  inputSchema: {
    type: 'object',
    properties: { projectId: { type: 'string' }, name: { type: 'string' }, expectedSourceRevision: { type: 'string' }, offset: { type: 'number' }, maxCodeUnits: { type: 'number' } },
    required: ['name'], additionalProperties: false,
  },
  readOnly: true,
};

export function workspaceHandlers(controller: PlaygroundController) {
  return {
    listProjects: (input: { cursor?: string; limit?: number }) => controller.listProjects(input),
    readProject: (input: { projectId?: string; expectedRevision?: string; cursor?: string; limit?: number }) => controller.readProject(input),
    readFile: (input: { projectId?: string; name: string; expectedSourceRevision?: string; offset?: number; maxCodeUnits?: number }) => controller.readFile(input),
  };
}
