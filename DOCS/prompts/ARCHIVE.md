# Archive entry-point

You are archiving a finished implementation plan for `circ-compiler`. Every phase is shipped, every slice is committed, and the working loop in `DOCS/PLANS_PROMPT.md` has nothing left to dispatch. Your job is to fold the planning artefacts into a single highlight document under `DOCS/archive/`, record the git hash that pins the canonical state, and remove the now-redundant source files.

You do not commit, push, or run any write `git` or `gh` command. Read-only `git` is fine. The human commits the archive, the deletions, and any STATUS entry as one reviewable change.

## When to invoke this prompt

Only when **all** of the following are true:

- The latest entry in `DOCS/STATUS.md` declares the plan complete (e.g. "v0 sign-off", "all phases shipped") with no pending next slice.
- `git log --oneline` confirms every slice STATUS claims as shipped is in the tree.
- `zig build test` passes on the current `HEAD`.
- The user has explicitly asked to archive (do not archive proactively).

If any of these is false, stop and tell the user what is missing instead of archiving.

## What you are archiving

A "plan" is the bundle of three artefact kinds that drove the implementation:

1. **The plan prompt** — `DOCS/PLANS_PROMPT.md`. Contains the project description, architectural anchors, engineering rules, phase index, working loop, recurring traps.
2. **The phase plans** — every `DOCS/PLANS/PHASE_<N>_*.md`. Each one decomposes a phase into slices with explicit deliverables and tests.
3. **The rolling status log** — `DOCS/STATUS.md`. Every shipped slice has a dated entry (`YYYY-MM-DD — Phase N — <slice title>` with `What shipped` / `Files touched` / `Tests` / `Next slice` / `Notes`).

Treat the three as a single bundle. The plan's name is the slug of `PLANS_PROMPT.md` — for the v0 work, use `v0`.

## Steps

### 1. Pick the plan name

Default: `v0`. If the user supplies a different name, use that. The archive file becomes `DOCS/archive/plan-<name>.md`. If `DOCS/archive/plan-<name>.md` already exists, stop and ask the user — never overwrite an existing archive.

### 2. Capture the canonical git hash

Run `git rev-parse HEAD` and `git log -1 --pretty='%h %s'`. Use the **full** SHA as the canonical reference. Embed both the full SHA and the short hash + subject in the archive header so a human can grep for either.

If `git status --porcelain` shows uncommitted changes that affect the plan files (`DOCS/PLANS_PROMPT.md`, `DOCS/PLANS/`, `DOCS/STATUS.md`), stop and ask the user to commit them first — the hash must point at a tree that contains the plan in its final state.

### 3. Read the bundle

In this order, with no agent delegation (you need the literal text):

1. `DOCS/PLANS_PROMPT.md` — full file.
2. Every `DOCS/PLANS/PHASE_<N>_*.md` — full file, in numerical order.
3. `DOCS/STATUS.md` — full file.

For large STATUS logs, read in offsets to stay under the read-tool cap; do not summarise from a partial read.

### 4. Write `DOCS/archive/plan-<name>.md`

Mandatory header:

```markdown
# Archived plan: <name>

**Canonical commit:** `<full-sha>` (`<short> <subject>`)
**Archived on:** <YYYY-MM-DD>
**Plan duration:** <first STATUS date> → <last STATUS date>

> This file is a highlight view. The full plan prompt, every phase plan, and every STATUS entry are preserved in the commit referenced above. Check that commit out (`git show <full-sha>:DOCS/PLANS_PROMPT.md`, etc.) when you need the unabridged source.
```

Mandatory body sections, in this order:

1. **Goal & scope** — one paragraph distilled from `PLANS_PROMPT.md`'s "What is being built" section. Keep the architectural anchors that constrained the work (e.g., "compiled artifacts are fixed at compile time", "no runtime topology mutation"). Drop process language ("read in this order on a cold start", "STATUS entry template") — that is gone with the working loop.
2. **Phase-by-phase highlights** — one subsection per phase. For each phase write:
   - One sentence from the phase plan's "Goal" / "What ships" section.
   - The bullet list of *what actually shipped*, distilled from the STATUS entries for that phase (one bullet per slice, ≤ 200 chars each). Quote diagnostic codes, file paths, and test names verbatim — those are durable references; rewording them strips usefulness. Do NOT repeat per-slice "Files touched" lists; mention only files whose name is itself the load-bearing decision (e.g., a fixture filename that captures the regression).
   - Any "definition of done" deviations or open questions that landed differently than the phase plan predicted.
3. **Diagnostic / API surface frozen at v0** — a single table or bullet list pulled from STATUS or `DOCS/decisions/`: every stable diagnostic code (`E001`–`E0NN`, `W0NN`), every emitted runtime export, every CLI flag. This is the reference future readers will grep for first.
4. **Known v0 papercuts carried forward** — reproduce the "Notes" callouts from STATUS that flag deferred work or v1 candidates (e.g., "single-file CLI mode skips `scan_imports`", "no programmatic root-pin id helper"). Each papercut gets one bullet with enough context to act on without re-reading STATUS.
5. **Decisions & specs that survived the plan** — pointers (not copies) to `DOCS/architecture.md`, `DOCS/circuit-format.md`, `DOCS/wasm-api.md`, `DOCS/simulation-engine.md`, `DOCS/decisions/`. The archive is for plan-process artefacts, not the living specs.

Style rules:

- "Highlight view" means: dense, durable, greppable. Every sentence should pay rent in a year. Cut session-by-session narration ("then we fixed the LED fan-out bug"); keep the durable artefact ("`regression_led_out_drives_gate.circ` exercises `led.out → and → output`").
- Preserve verbatim: diagnostic codes, file paths, test names, fixture names, CLI flag names, exported function names. These are how future you will search.
- Strip: dates of individual slices (already pinned by the canonical commit), STATUS-template scaffolding, "Next slice" lines, intermediate test counts.
- Aim for one screenful per phase. If a phase wrote 30 slices, the archive does not need 30 bullets — group by deliverable kind ("fixtures", "validator passes", "emitter modules") and bullet that.

### 5. Clean up the consolidated sources

After the archive file is written and the user has reviewed it (you stop for review at this point — see Working loop below), the sources that fed the archive are deleted in the same review:

- `DOCS/PLANS_PROMPT.md`
- Every file under `DOCS/PLANS/`
- `DOCS/STATUS.md`

`DOCS/index.md` and any other doc that points at these files gets its pointer removed (or repointed at `DOCS/archive/index.md`). Add a row for the new archive file to `DOCS/archive/index.md`. Do **not** delete `DOCS/decisions/`, `DOCS/architecture.md`, `DOCS/circuit-format.md`, `DOCS/wasm-api.md`, `DOCS/simulation-engine.md`, or anything under `DOCS/getting-started.md` — those are living specs, not plan artefacts.

If the repository contains a `DOCS/prompts/ARCHIVE.md` (this file), keep it. The archive prompt is a process artefact for *future* plans and survives across plan cycles.

Use `git status` to confirm the only modifications/deletions are the ones listed above. If anything else has changed, stop and surface it to the user before they commit.

### 6. Verify

Run `zig build test` one final time. The archive must not break the build (it shouldn't — only docs moved — but the suite is the bar). If anything fails, stop and report; do not commit a broken tree even by accident via the human.

## Working loop

For each archive session:

1. Read the latest `DOCS/STATUS.md` entry. Confirm "plan complete" language. If it says "Next slice: <something concrete>", stop — the plan is not finished.
2. Run `git status` and `git log --oneline -10`. Plan files must be clean. Latest commit should be the slice that signed off the plan.
3. Run `git rev-parse HEAD` and capture the SHA.
4. Read the bundle (PLANS_PROMPT, every PHASE plan, STATUS). Distil into `DOCS/archive/plan-<name>.md` per Step 4.
5. **Stop for human review of the archive file before deleting anything.** Do not bundle the archive write and the source deletions in one un-reviewed shot — the archive's quality is what determines whether the deletions are safe.
6. After the human approves, perform the cleanup (Step 5) and run `zig build test` (Step 6). The human commits the archive write + deletions + any pointer fix in `DOCS/index.md` as one reviewable change.

## What this file is not

- Not a phase plan or implementation prompt. It does not produce code or tests; it produces a single document.
- Not authorization for commits, pushes, or destructive git actions.
- Not a substitute for `DOCS/decisions/`. The archive captures the *plan*, not the *spec*. Specs stay in their own files and remain authoritative.
