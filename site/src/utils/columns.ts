// The compiler reports columns as 1-based BYTE offsets into the line
// (lib/syntax/translate.zig offsetToLineCol); a <textarea> selection is in
// UTF-16 code units. Convert per line, never assume ASCII.

/** 1-based byte column → 1-based UTF-16 column on `line`; past-end clamps to line.length + 1. */
export function byteColToUtf16(line: string, byteCol: number): number {
  let bytes = 0;
  let units = 0;
  const target = byteCol - 1;
  for (const ch of line) {
    if (bytes >= target) break;
    const cp = ch.codePointAt(0)!;
    bytes += cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4;
    units += ch.length;
  }
  return Math.min(units, line.length) + 1;
}

/** Caret offset (UTF-16) of `line0` (0-based) + `utf16Col` (1-based) in `text` (LF-normalised). */
export function caretOffset(text: string, line0: number, utf16Col: number): number {
  const lines = text.split('\n');
  let offset = 0;
  for (let i = 0; i < line0 && i < lines.length; i++) offset += lines[i].length + 1;
  const line = lines[Math.min(line0, lines.length - 1)] ?? '';
  return offset + Math.min(utf16Col - 1, line.length);
}
