import type { ArtifactId, OperationKind, ProjectVersion, Revision, TargetRef, WorkInputs } from './playground-contract.ts';

export interface SourceFile { name: string; body: string; }

export interface ProjectInputs {
  id: string;
  name: string;
  files: readonly SourceFile[];
  images: ReadonlyMap<string, ReadonlyMap<string, string>>;
}

export class RevisionAllocator {
  private sequence = 0;

  constructor(private readonly pageId: string) {}

  next(kind: string): Revision {
    this.sequence += 1;
    return `${this.pageId}:${kind}:${this.sequence}`;
  }
}

export function sameSource(left: readonly SourceFile[], right: readonly SourceFile[]): boolean {
  return left.length === right.length && left.every((file, index) => file.name === right[index]?.name && file.body === right[index]?.body);
}

export function sameImages(
  left: ReadonlyMap<string, ReadonlyMap<string, string>>,
  right: ReadonlyMap<string, ReadonlyMap<string, string>>,
): boolean {
  if (left.size !== right.size) return false;
  for (const [file, images] of left) {
    const other = right.get(file);
    if (!other || images.size !== other.size) return false;
    for (const [name, text] of images) if (other.get(name) !== text) return false;
  }
  return true;
}

export function copyFiles(files: readonly SourceFile[]): SourceFile[] {
  return files.map((file) => ({ name: file.name, body: file.body }));
}

export function copyImages(images: ReadonlyMap<string, ReadonlyMap<string, string>>): Map<string, Map<string, string>> {
  return new Map([...images].map(([file, values]) => [file, new Map(values)]));
}

export function copyWorkInputs(inputs: WorkInputs): WorkInputs {
  return {
    ...inputs,
    target: { ...inputs.target },
  };
}

export function sameArtifactPayload(
  left: Uint8Array,
  right: Uint8Array,
  leftFileIds: ReadonlyMap<string, number>,
  rightFileIds: ReadonlyMap<string, number>,
): boolean {
  if (left.byteLength !== right.byteLength || leftFileIds.size !== rightFileIds.size) return false;
  for (let index = 0; index < left.byteLength; index += 1) if (left[index] !== right[index]) return false;
  for (const [name, id] of leftFileIds) if (rightFileIds.get(name) !== id) return false;
  return true;
}

interface TrackedProject {
  inputs: ProjectInputs;
  version: ProjectVersion;
}

export class RevisionTracker {
  private readonly projects = new Map<string, TrackedProject>();
  private readonly optionValues = new Map<OperationKind, string>();
  private readonly optionRevisions = new Map<OperationKind, Revision>();
  private target: TargetRef | null = null;
  private _observationRevision: Revision;

  constructor(private readonly ids: RevisionAllocator) {
    this._observationRevision = ids.next('observation');
  }

  get observationRevision(): Revision { return this._observationRevision; }
  get currentTarget(): TargetRef | null { return this.target && { ...this.target }; }

  observeProject(inputs: ProjectInputs): ProjectVersion {
    const previous = this.projects.get(inputs.id);
    if (!previous) {
      const version = {
        projectId: inputs.id,
        revision: this.ids.next('project'),
        sourceRevision: this.ids.next('source'),
        imageRevision: this.ids.next('image'),
      };
      this.projects.set(inputs.id, { inputs: { ...inputs, files: copyFiles(inputs.files), images: copyImages(inputs.images) }, version });
      this.bumpObservation();
      return { ...version };
    }
    const sourceChanged = !sameSource(previous.inputs.files, inputs.files);
    const imagesChanged = !sameImages(previous.inputs.images, inputs.images);
    const nameChanged = previous.inputs.name !== inputs.name;
    if (!sourceChanged && !imagesChanged && !nameChanged) return { ...previous.version };
    const version = {
      projectId: inputs.id,
      revision: this.ids.next('project'),
      sourceRevision: sourceChanged ? this.ids.next('source') : previous.version.sourceRevision,
      imageRevision: imagesChanged ? this.ids.next('image') : previous.version.imageRevision,
    };
    this.projects.set(inputs.id, { inputs: { ...inputs, files: copyFiles(inputs.files), images: copyImages(inputs.images) }, version });
    if (this.target?.projectId === inputs.id && sourceChanged) {
      this.target = { ...this.target, sourceRevision: version.sourceRevision };
    }
    this.bumpObservation();
    return { ...version };
  }

  projectVersion(projectId: string): ProjectVersion | null {
    const version = this.projects.get(projectId)?.version;
    return version ? { ...version } : null;
  }

  selectTarget(projectId: string, entryFile: string): TargetRef {
    const version = this.projects.get(projectId)?.version;
    if (!version) throw new Error(`Unknown project: ${projectId}`);
    this.target = { projectId, sourceRevision: version.sourceRevision, entryFile, targetEpoch: this.ids.next('target') };
    this.bumpObservation();
    return { ...this.target };
  }

  optionsRevision(kind: OperationKind, value: unknown): Revision {
    const projection = JSON.stringify(value);
    const previous = this.optionValues.get(kind);
    const revision = this.optionRevisions.get(kind);
    if (previous === projection && revision) return revision;
    const next = this.ids.next(`options-${kind}`);
    this.optionValues.set(kind, projection);
    this.optionRevisions.set(kind, next);
    return next;
  }

  private bumpObservation(): void { this._observationRevision = this.ids.next('observation'); }
}

export function capturedInputs(inputs: WorkInputs): WorkInputs { return copyWorkInputs(inputs); }

export function artifactMayBeReused(
  existing: { id: ArtifactId; bytes: Uint8Array; fileIds: ReadonlyMap<string, number> },
  incoming: { bytes: Uint8Array; fileIds: ReadonlyMap<string, number> },
): ArtifactId | null {
  return sameArtifactPayload(existing.bytes, incoming.bytes, existing.fileIds, incoming.fileIds) ? existing.id : null;
}
