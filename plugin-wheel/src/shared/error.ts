// FR-005: Cross-plugin importable error types
export class WheelError extends Error {
  public readonly code: string;
  public readonly context: Record<string, unknown>;

  constructor(code: string, message: string, context: Record<string, unknown> = {}) {
    super(message);
    this.name = 'WheelError';
    this.code = code;
    this.context = context;
  }
}

// FR-005: State file not found
export class StateNotFoundError extends WheelError {
  constructor(path: string, message?: string) {
    super(
      'STATE_NOT_FOUND',
      message ?? `State file not found: ${path}`,
      { path }
    );
    this.name = 'StateNotFoundError';
  }
}

// FR-005: JSON malformed or jq path invalid
export class ValidationError extends WheelError {
  constructor(path: string, reason: string) {
    super('VALIDATION_ERROR', `Validation failed at path '${path}': ${reason}`, { path, reason });
    this.name = 'ValidationError';
  }
}

// FR-005: mkdir-based locking failure
export class LockError extends WheelError {
  constructor(lockPath: string, reason: string) {
    super('LOCK_ERROR', `Lock error on '${lockPath}': ${reason}`, { lockPath, reason });
    this.name = 'LockError';
  }
}