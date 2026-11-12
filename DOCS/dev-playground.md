# The dev playground

`tools/playground` starts the site's playground as a compiler development
tool. It differs from `/playground` on the site in two ways: its projects are
directories on disk, and its compiler is built from the working tree.

```sh
tools/playground                      # tests/fixtures/projects
tools/playground path/to/circuits     # any directory, relative to where you run it
tools/playground . --port 4400        # flags after the directory go to `astro dev`
tools/playground --no-open            # do not open the browser
```

It needs `bun` (with `site/` installed) and `zig` on `PATH`. From `site/`,
`bun run playground` is the same command. Neither `astro dev` nor any build
loads this code: `site/astro.config.mjs` adds the plugin only when the
launcher sets `CIRC_PLAYGROUND_ROOT`.

## Projects on disk

Each directory under the workspace that directly holds `.circ` files is one
project, listed under **Mine** in the workspace switcher by its path. Its tabs
are that directory's `.circ` files. A project opens on the file no sibling
imports; among several, `root.circ`, `main.circ`, or the file named after the
directory wins. The playground compiles whichever tab is open as the entry
file, as it does on the site.

The playground saves as you type, half a second after the last keystroke, and
writes only the files whose text changed. Opening a project writes nothing.

| In the playground        | On disk                                               |
| ------------------------ | ----------------------------------------------------- |
| Edit a tab               | That file is rewritten.                               |
| Add a tab                | A new `.circ` file appears in the directory.          |
| Rename a tab             | The new file is written and the old one is trashed.   |
| Delete a tab             | The file is trashed.                                  |
| New circuit, or a fork of an example | A new directory named after the project.  |
| Rename a project         | Its `.circ` files move to the directory the new name maps to. |
| Delete a project         | Its `.circ` files are trashed.                        |

**Nothing is unlinked.** A trashed file moves to
`.circ-trash/<timestamp>/<its path>` inside the workspace, which git ignores.
Editing touches `.circ` files only; a memory image or a note beside them
stays where it is unless a `save` names it.

## Memory images: `load` and `save`

The console's `load <mem> <path>` and `save <mem> <path>` work here as they
do under `circ-compile --sim`; the site's playground refuses both. A path is
relative to the open project's directory (to the workspace root for an
example or a tour step), may climb with `..`, and must stay inside the
workspace. Start the tool one level up when the images live beside the
projects:

```sh
tools/playground tests/fixtures
```

```
load mem ../../mem/sharp_ram_ra.bin
save mem ram.bin
```

A `save` over an existing file moves the old file to the trash first. A path
that leaves the workspace, or enters a dotted directory, answers
`err E_IO <path>: AccessDenied`.

## Outside changes

A change made outside the page (an editor, a `git checkout`) reloads the page,
after it writes any edit still pending.

Three limits to know:

* A project is one flat directory. An import that reaches outside it
  (`"../lib/x.circ"`) does not resolve, exactly as on the site.
* The playground holds a project as one text with `// name.circ` marker
  lines between files. A file with a comment that reads like such a marker in
  the middle of its body cannot be told apart from two files, so that project
  is left out; the browser console names it.
* The size caps of the site's playground (16 projects, 32 KiB each) do not
  apply. Layout and settings still live in the browser, under a key of their
  own, so they never mix with a plain `astro dev` session.

## The compiler

The page loads `zig-out/lib/libcirc.wasm`, not the committed copy in
`site/public/wasm/`. The launcher runs `zig build libcirc-wasm` at startup
and again whenever a `.zig`, `.circ`, `.peg`, or `.zon` file changes under
`lib/`, `templates/`, `build/`, or `cmd/`, or when `build.zig` changes. A
successful build reloads the page, which comes back on the same project. A failed build prints the compiler's output in the terminal, shows it
over the page, and leaves the last good module in place.

The committed `site/public/wasm/libcirc.wasm` is never touched; refresh that
one with `bun run libcirc` at release time.

## Where the code lives

| File | Role |
| --- | --- |
| `tools/playground`, `site/scripts/dev-playground.ts` | The launcher. |
| `site/scripts/dev-playground/plugin.mjs` | The Vite plugin: workspace and image routes, file watchers, compiler rebuilds. It answers only requests from its own page. |
| `site/src/utils/disk-projects.ts` | Directory to project and back; plans the writes for an edit. Pure. |
| `site/src/scripts/disk-storage.ts` | The storage the playground's store reads and writes through, and the console's file source. |
| `site/test/disk-projects.test.ts` | Tests for all of the above. |
