import { isFileName, joinConflicts, joinFiles, splitFiles, type NamedFile } from '../utils/split-files.ts';
import { seedBody } from './file-tabs.ts';

export const MAX_PROJECT_FILES = 128;
export const MAX_PROJECT_NAME_CODE_UNITS = 120;
export const MAX_AGENT_FILE_NAME_CODE_UNITS = 256;
export const MAX_FILE_MUTATIONS = 64;
export const MAX_TEXT_EDITS = 256;

export type TextEdit = { from: number; to: number; text: string };
export type FileMutation =
  | { kind: 'edit'; name: string; edits: TextEdit[] }
  | { kind: 'create'; name: string; body?: string; before?: string | null }
  | { kind: 'rename'; name: string; newName: string }
  | { kind: 'delete'; name: string };

export type MutationFailure = { operation: number; file?: string; reason: string };
export type MutationPlan = {
  files: NamedFile[];
  active: number;
  changed: boolean;
  renamed: { oldName: string; newName: string }[];
  deleted: string[];
  created: string[];
};

const encoder = new TextEncoder();

export function isWellFormed(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code >= 0xd800 && code <= 0xdbff) {
      if (index + 1 >= value.length || value.charCodeAt(index + 1) < 0xdc00 || value.charCodeAt(index + 1) > 0xdfff) return false;
      index += 1;
    } else if (code >= 0xdc00 && code <= 0xdfff) return false;
  }
  return true;
}

export function utf8Bytes(value: string): number { return encoder.encode(value).byteLength; }

export function validProjectName(value: string): string | null {
  const trimmed = value.trim();
  return trimmed && trimmed.length <= MAX_PROJECT_NAME_CODE_UNITS && isWellFormed(trimmed) && !/[\u0000-\u001f\u007f-\u009f]/.test(trimmed) ? trimmed : null;
}

export function validFileName(value: string): boolean {
  return value.length <= MAX_AGENT_FILE_NAME_CODE_UNITS && isWellFormed(value) && isFileName(value);
}

function failure(operation: number, reason: string, file?: string): { ok: false; error: MutationFailure } {
  return { ok: false, error: { operation, ...(file ? { file } : {}), reason } };
}

function scalarBoundary(text: string, offset: number): boolean {
  return offset >= 0 && offset <= text.length && !(offset > 0 && offset < text.length && /[\uD800-\uDBFF]/.test(text[offset - 1]!) && /[\uDC00-\uDFFF]/.test(text[offset]!));
}

function applyEdits(body: string, edits: TextEdit[], operation: number, name: string): { ok: true; body: string } | { ok: false; error: MutationFailure } {
  if (edits.length === 0) return failure(operation, 'edit requires at least one range', name);
  let previous = -1;
  for (const edit of edits) {
    if (!Number.isSafeInteger(edit.from) || !Number.isSafeInteger(edit.to) || typeof edit.text !== 'string' || !isWellFormed(edit.text)) return failure(operation, 'edit range or replacement is invalid', name);
    if (edit.from < 0 || edit.to < edit.from || edit.to > body.length || !scalarBoundary(body, edit.from) || !scalarBoundary(body, edit.to)) return failure(operation, 'edit range is outside a Unicode scalar boundary', name);
    if (edit.from < previous || (edit.from === previous && edit.from === edit.to)) return failure(operation, 'edits overlap or duplicate an insertion offset', name);
    previous = edit.to;
  }
  let next = body;
  for (let index = edits.length - 1; index >= 0; index -= 1) {
    const edit = edits[index];
    next = next.slice(0, edit.from) + edit.text + next.slice(edit.to);
  }
  return { ok: true, body: next };
}

/** Validate a complete ordered operation batch before any live workspace state changes. */
export function planMutations(
  initial: readonly NamedFile[],
  activeName: string,
  operations: readonly FileMutation[],
): { ok: true; value: MutationPlan } | { ok: false; error: MutationFailure } {
  if (operations.length < 1 || operations.length > MAX_FILE_MUTATIONS) return failure(-1, `operations must contain 1 through ${MAX_FILE_MUTATIONS} entries`);
  if (operations.reduce((count, operation) => count + (operation.kind === 'edit' ? operation.edits.length : 0), 0) > MAX_TEXT_EDITS) return failure(-1, `at most ${MAX_TEXT_EDITS} text edits are allowed`);
  const files = initial.map((file) => ({ ...file }));
  let active = files.findIndex((file) => file.name === activeName);
  if (active < 0) active = Math.max(0, files.length - 1);
  const renamed: MutationPlan['renamed'] = [];
  const deleted: string[] = [];
  const created: string[] = [];
  let destructive = false;

  for (let operationIndex = 0; operationIndex < operations.length; operationIndex += 1) {
    const operation = operations[operationIndex];
    if (!operation || typeof operation !== 'object' || !('kind' in operation)) return failure(operationIndex, 'operation is invalid');
    if (operation.kind === 'edit') {
      const index = files.findIndex((file) => file.name === operation.name);
      if (index < 0) return failure(operationIndex, 'file does not exist', operation.name);
      const edited = applyEdits(files[index].body, operation.edits, operationIndex, operation.name);
      if (!edited.ok) return edited;
      files[index] = { ...files[index], body: edited.body };
    } else if (operation.kind === 'create') {
      if (!validFileName(operation.name) || files.some((file) => file.name === operation.name)) return failure(operationIndex, 'file name is invalid or already exists', operation.name);
      const body = operation.body ?? seedBody(operation.name);
      if (!isWellFormed(body)) return failure(operationIndex, 'file body is not well-formed UTF-16', operation.name);
      const before = operation.before === undefined ? files.length - 1 : operation.before === null ? files.length : files.findIndex((file) => file.name === operation.before);
      if (before < 0) return failure(operationIndex, 'before file does not exist', operation.name);
      files.splice(before, 0, { name: operation.name, body });
      if (before <= active) active += 1;
      created.push(operation.name);
      destructive = true;
    } else if (operation.kind === 'rename') {
      const index = files.findIndex((file) => file.name === operation.name);
      if (index < 0 || !validFileName(operation.newName) || files.some((file, candidate) => candidate !== index && file.name === operation.newName)) return failure(operationIndex, 'rename references a missing or conflicting file', operation.name);
      if (operation.name !== operation.newName) {
        files[index] = { ...files[index], name: operation.newName };
        renamed.push({ oldName: operation.name, newName: operation.newName });
      }
    } else if (operation.kind === 'delete') {
      const index = files.findIndex((file) => file.name === operation.name);
      if (index < 0 || files.length === 1) return failure(operationIndex, 'file does not exist or is the last file', operation.name);
      files.splice(index, 1);
      if (index < active) active -= 1;
      else if (index === active) active = Math.min(index, files.length - 1);
      deleted.push(operation.name);
      destructive = true;
    } else return failure(operationIndex, 'unknown operation kind');
  }

  const conflicts = joinConflicts(files);
  if (conflicts.length || files.length > MAX_PROJECT_FILES) return failure(-1, conflicts[0]?.reason ?? `project may contain at most ${MAX_PROJECT_FILES} files`, files[conflicts[0]?.index ?? 0]?.name);
  const roundTrip = splitFiles(joinFiles(files)).map(({ name, body }) => ({ name, body }));
  if (roundTrip.length !== files.length || roundTrip.some((file, index) => file.name !== files[index].name || file.body !== files[index].body)) return failure(-1, 'files cannot round-trip through the project marker format');
  const sourceChanged = files.length !== initial.length || files.some((file, index) => file.name !== initial[index]?.name || file.body !== initial[index]?.body);
  if (!sourceChanged && destructive) return failure(-1, 'a delete/recreate batch cannot be accepted as an identity-destroying no-op');
  return { ok: true, value: { files, active, changed: sourceChanged, renamed, deleted, created } };
}
