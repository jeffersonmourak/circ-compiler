// Display and indentation preferences, independent of compiler options.
export interface EditorPreferences {
  wrapLines: boolean;
  fontSize: number;
  tabSize: number;
}

export const DEFAULT_EDITOR_PREFERENCES: Readonly<EditorPreferences> = {
  wrapLines: true,
  fontSize: 14,
  tabSize: 2,
};

export function normalizeEditorPreferences(raw: unknown): EditorPreferences {
  const value = typeof raw === 'object' && raw !== null && !Array.isArray(raw)
    ? raw as Record<string, unknown> : {};
  const whole = (n: unknown, fallback: number, min: number, max: number) =>
    typeof n === 'number' && Number.isFinite(n) ? Math.max(min, Math.min(max, Math.round(n))) : fallback;
  return {
    wrapLines: typeof value.wrapLines === 'boolean' ? value.wrapLines : DEFAULT_EDITOR_PREFERENCES.wrapLines,
    fontSize: whole(value.fontSize, DEFAULT_EDITOR_PREFERENCES.fontSize, 10, 24),
    tabSize: whole(value.tabSize, DEFAULT_EDITOR_PREFERENCES.tabSize, 1, 8),
  };
}
