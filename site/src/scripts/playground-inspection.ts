import {
  DEFAULT_TEXT_PAGE_CODE_UNITS,
  DEFAULT_TRUTH_PAGE_ROWS,
  MAX_RETAINED_SCHEMATICS,
  MAX_RETAINED_TRUTH_BYTES,
  MAX_RETAINED_TRUTH_RESULTS,
  MAX_SCHEMATIC_RESULT_BYTES,
  MAX_TRUTH_PAGE_ROWS,
  MAX_TRUTH_RESULT_BYTES,
  type SchematicPage,
  type TruthPage,
} from './playground-contract.ts';

const encoder = new TextEncoder();

/** Never split a surrogate pair while paging browser strings. */
export function textPage(text: string, offset = 0, target = DEFAULT_TEXT_PAGE_CODE_UNITS) {
  if (!Number.isSafeInteger(offset) || offset < 0 || offset > text.length || !Number.isSafeInteger(target) || target < 1 || target > 24 * 1024) return null;
  let end = Math.min(text.length, offset + target);
  if (end < text.length && end > offset && /[\uD800-\uDBFF]/.test(text[end - 1])) end -= 1;
  if (end === offset && end < text.length) end += 2;
  return { text: text.slice(offset, end), nextCursor: end < text.length ? String(end) : null };
}

export function schematicDimensions(text: string) {
  const lines = text === '' ? [] : text.replace(/\n$/, '').split('\n');
  return { rows: lines.length, columns: lines.reduce((max, line) => Math.max(max, line.length), 0), codeUnits: text.length, utf8Bytes: encoder.encode(text).byteLength };
}

export interface RetainedSchematic { operationId: string; page: Omit<SchematicPage, 'text' | 'nextCursor'> & { text: string }; }
export class SchematicResults {
  private values = new Map<string, RetainedSchematic>();
  admit(value: RetainedSchematic): boolean {
    if (encoder.encode(value.page.text).byteLength > MAX_SCHEMATIC_RESULT_BYTES) return false;
    this.values.set(value.operationId, value);
    while (this.values.size > MAX_RETAINED_SCHEMATICS) this.values.delete(this.values.keys().next().value!);
    return this.values.has(value.operationId);
  }
  get(operationId: string, cursor?: string, maxCodeUnits?: number): SchematicPage | null {
    const retained = this.values.get(operationId);
    const page = retained && textPage(retained.page.text, cursor === undefined ? 0 : Number(cursor), maxCodeUnits ?? DEFAULT_TEXT_PAGE_CODE_UNITS);
    return retained && page ? { ...retained.page, text: page.text, nextCursor: page.nextCursor } : null;
  }
}

export interface RetainedTruth { operationId: string; page: Omit<TruthPage, 'rows' | 'nextCursor'> & { rows: TruthPage['rows'] }; }
export class TruthResults {
  private values = new Map<string, RetainedTruth>();
  admit(value: RetainedTruth): boolean {
    if (encoder.encode(JSON.stringify(value)).byteLength > MAX_TRUTH_RESULT_BYTES) return false;
    this.values.set(value.operationId, value);
    while (this.values.size > MAX_RETAINED_TRUTH_RESULTS || this.bytes() > MAX_RETAINED_TRUTH_BYTES) this.values.delete(this.values.keys().next().value!);
    return this.values.has(value.operationId);
  }
  get(operationId: string, cursor?: string, limit = DEFAULT_TRUTH_PAGE_ROWS): TruthPage | null {
    const retained = this.values.get(operationId);
    const start = cursor === undefined ? 0 : Number(cursor);
    if (!retained || !Number.isSafeInteger(start) || start < 0 || start > retained.page.rows.length || !Number.isSafeInteger(limit) || limit < 1 || limit > MAX_TRUTH_PAGE_ROWS) return null;
    const rows = retained.page.rows.slice(start, start + limit);
    return { ...retained.page, rows, nextCursor: start + rows.length < retained.page.rows.length ? String(start + rows.length) : null };
  }
  private bytes() { return [...this.values.values()].reduce((total, value) => total + encoder.encode(JSON.stringify(value)).byteLength, 0); }
}
