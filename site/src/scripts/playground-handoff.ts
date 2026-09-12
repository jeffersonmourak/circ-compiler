import { DEFAULT_TEXT_PAGE_CODE_UNITS, type ExportOmission, type TextExportPage } from './playground-contract.ts';
import { textPage } from './playground-inspection.ts';

export const SOURCE_OMISSIONS: ExportOmission[] = ['source_images', 'live_ram', 'live_pin_state', 'active_entry_selection', 'settings', 'transcript', 'compiled_artifact'];
export function pageExport(snapshot: Omit<TextExportPage, 'text' | 'nextCursor'> & { text: string }, cursor?: string, maxCodeUnits = DEFAULT_TEXT_PAGE_CODE_UNITS): TextExportPage | null {
  const page = textPage(snapshot.text, cursor === undefined ? 0 : Number(cursor), maxCodeUnits);
  return page ? { ...snapshot, text: page.text, nextCursor: page.nextCursor } : null;
}

/** Browser dispatch has no completion signal; this only reports a click issued. */
export function dispatchDownload(anchorParent: HTMLElement, filename: string, bytes: Uint8Array, type: 'application/wasm' | 'application/octet-stream'): boolean {
  try {
    const blob = new Blob([bytes.slice() as BlobPart], { type });
    const href = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = href; anchor.download = filename; anchor.hidden = true;
    anchorParent.appendChild(anchor); anchor.click(); anchor.remove();
    window.setTimeout(() => URL.revokeObjectURL(href), 1000);
    return true;
  } catch { return false; }
}
