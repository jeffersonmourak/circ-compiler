import { describe, expect, test } from 'bun:test';
import { RevisionAllocator, RevisionTracker, artifactMayBeReused, copyImages } from '../src/scripts/playground-revisions.ts';

function project(body = 'out = not(a)', name = 'Example', images = new Map<string, Map<string, string>>()) {
  return { id: 'example:one', name, files: [{ name: 'main.circ', body }], images };
}

describe('playground revisions', () => {
  test('source_revision_tracks_only_named_source', () => {
    const tracker = new RevisionTracker(new RevisionAllocator('page'));
    const first = tracker.observeProject(project());
    expect(tracker.observeProject(project('out = not(a)', 'Renamed')).sourceRevision).toBe(first.sourceRevision);
    expect(tracker.observeProject(project('out = not(b)', 'Renamed')).sourceRevision).not.toBe(first.sourceRevision);
  });

  test('project_revision_covers_metadata_and_images', () => {
    const tracker = new RevisionTracker(new RevisionAllocator('page'));
    const first = tracker.observeProject(project());
    const renamed = tracker.observeProject(project('out = not(a)', 'Renamed'));
    const imaged = tracker.observeProject(project('out = not(a)', 'Renamed', new Map([['main.circ', new Map([['rom', '01']])]])));
    expect(renamed.revision).not.toBe(first.revision);
    expect(renamed.imageRevision).toBe(first.imageRevision);
    expect(imaged.revision).not.toBe(renamed.revision);
    expect(imaged.sourceRevision).toBe(renamed.sourceRevision);
    expect(imaged.imageRevision).not.toBe(renamed.imageRevision);
  });

  test('noop_and_undo_have_distinct_rules', () => {
    const tracker = new RevisionTracker(new RevisionAllocator('page'));
    const first = tracker.observeProject(project());
    expect(tracker.observeProject(project()).sourceRevision).toBe(first.sourceRevision);
    tracker.observeProject(project('out = not(b)'));
    expect(tracker.observeProject(project()).sourceRevision).not.toBe(first.sourceRevision);
  });

  test('target_epoch_prevents_switch_back_aba', () => {
    const tracker = new RevisionTracker(new RevisionAllocator('page'));
    tracker.observeProject(project());
    const first = tracker.selectTarget('example:one', 'main.circ');
    const second = tracker.selectTarget('example:one', 'other.circ');
    const third = tracker.selectTarget('example:one', 'main.circ');
    expect(second.targetEpoch).not.toBe(first.targetEpoch);
    expect(third.targetEpoch).not.toBe(first.targetEpoch);
    expect(third.sourceRevision).toBe(first.sourceRevision);
  });

  test('options_revision_is_per_operation', () => {
    const tracker = new RevisionTracker(new RevisionAllocator('page'));
    const compile = tracker.optionsRevision('compile', { warnings_as_errors: false });
    expect(tracker.optionsRevision('compile', { warnings_as_errors: false })).toBe(compile);
    expect(tracker.optionsRevision('preview', { expand_macros: false })).not.toBe(compile);
    expect(tracker.optionsRevision('compile', { warnings_as_errors: true })).not.toBe(compile);
  });

  test('snapshot_detaches_image_maps_and_equal_bytes_require_matching_mapping', () => {
    const images = new Map([['main.circ', new Map([['rom', '01']])]]);
    const detached = copyImages(images);
    images.get('main.circ')!.set('rom', '02');
    expect(detached.get('main.circ')!.get('rom')).toBe('01');
    const id = artifactMayBeReused(
      { id: 'artifact', bytes: new Uint8Array([1, 2]), fileIds: new Map([['main.circ', 1]]) },
      { bytes: new Uint8Array([1, 2]), fileIds: new Map([['main.circ', 1]]) },
    );
    expect(id).toBe('artifact');
    expect(artifactMayBeReused(
      { id: 'artifact', bytes: new Uint8Array([1, 2]), fileIds: new Map([['main.circ', 1]]) },
      { bytes: new Uint8Array([1, 3]), fileIds: new Map([['main.circ', 1]]) },
    )).toBeNull();
  });
});
