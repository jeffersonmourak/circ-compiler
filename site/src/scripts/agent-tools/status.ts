import type { PlaygroundController, ToolDescriptor } from '../playground-contract.ts';

export const statusDescriptor: ToolDescriptor = {
  name: 'circ_get_status',
  description: 'Read the open circ playground project and reported compiler status. Returns connection readiness and existing output availability. This operation does not compile or change the project; revision-verified freshness is reported as untracked in this release.',
  inputSchema: { type: 'object', properties: {}, required: [], additionalProperties: false },
  readOnly: true,
};

export function statusHandler(controller: PlaygroundController): () => unknown {
  return () => controller.getStatus();
}
