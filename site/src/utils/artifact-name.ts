// The file name a downloaded artifact gets.
//
// The CLI names its output after the source (`circ-compile adder.circ -o
// adder.wasm`); the playground names it after the project, since almost every
// project's root file is `main.circ` and a folder of `main.wasm`s tells the
// reader nothing. The label is whatever the tree shows — an example's title, a
// scratch project's name — reduced to what a file system and a shell are both
// comfortable with.

/** `Half adder` → `half-adder.wasm`; anything with no letters or digits left
 *  in it becomes `circuit.wasm`. */
export function artifactFileName(label: string, ext = '.wasm'): string {
  const stem = label
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '') // strip accents left over from NFKD
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 64)
    .replace(/-+$/g, '');
  return `${stem || 'circuit'}${ext}`;
}
