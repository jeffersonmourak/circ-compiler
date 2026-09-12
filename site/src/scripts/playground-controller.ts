import type { PlaygroundController, PlaygroundStatus, StatusReader } from './playground-contract.ts';

export class ControllerDisposedError extends Error {
  constructor() {
    super('The playground page has been disposed. Rediscover its tools after reload.');
  }
}

function cloneStatus(status: PlaygroundStatus): PlaygroundStatus {
  return JSON.parse(JSON.stringify(status)) as PlaygroundStatus;
}

export class PlaygroundControllerImpl implements PlaygroundController {
  private disposed = false;

  constructor(private readonly reader: StatusReader) {}

  getStatus(): PlaygroundStatus {
    if (this.disposed) throw new ControllerDisposedError();
    return cloneStatus(this.reader.read());
  }

  dispose(): void {
    this.disposed = true;
  }
}

export function createPlaygroundController(reader: StatusReader): PlaygroundController {
  return new PlaygroundControllerImpl(reader);
}
