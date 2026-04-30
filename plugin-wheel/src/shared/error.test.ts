// Scenario: S1 — WheelError, StateNotFoundError, ValidationError, LockError have correct codes and contexts
import { describe, it, expect } from 'vitest';
import { WheelError, StateNotFoundError, ValidationError, LockError } from './error.js';

describe('WheelError', () => {
  it('should have code FS_WRITE and context', () => { // FR-005
    const err = new WheelError('FS_WRITE', 'Failed to write', { path: '/test' });
    expect(err.code).toBe('FS_WRITE');
    expect(err.context.path).toBe('/test');
    expect(err.message).toBe('Failed to write');
  });
});

describe('StateNotFoundError', () => {
  it('should have code STATE_NOT_FOUND', () => { // FR-005
    const err = new StateNotFoundError('/test/path.json');
    expect(err.code).toBe('STATE_NOT_FOUND');
    expect(err.context.path).toBe('/test/path.json');
  });

  it('should use custom message if provided', () => { // FR-005
    const err = new StateNotFoundError('/test', 'custom message');
    expect(err.message).toBe('custom message');
  });
});

describe('ValidationError', () => {
  it('should have code VALIDATION_ERROR with path and reason', () => { // FR-005
    const err = new ValidationError('.foo', 'path not found');
    expect(err.code).toBe('VALIDATION_ERROR');
    expect(err.context.path).toBe('.foo');
    expect(err.context.reason).toBe('path not found');
  });
});

describe('LockError', () => {
  it('should have code LOCK_ERROR with lockPath', () => { // FR-005
    const err = new LockError('/test/lock', 'already held');
    expect(err.code).toBe('LOCK_ERROR');
    expect(err.context.lockPath).toBe('/test/lock');
    expect(err.context.reason).toBe('already held');
  });
});