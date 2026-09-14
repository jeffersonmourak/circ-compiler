export const NO_SETTLE_MESSAGE = 'settle work budget exceeded; reset required';

export class NoSettleError extends Error {
  constructor() {
    super(`E_NOSETTLE: ${NO_SETTLE_MESSAGE}`);
    this.name = 'NoSettleError';
  }
}
