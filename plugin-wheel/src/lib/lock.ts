// FR-006: mkdir-based locking utilities
import { promises as fs } from 'fs';
import { LockError } from '../shared/error.js';

// FR-006: acquireLock(lockPath: string, ttlMs?: number): Promise<boolean>
export async function acquireLock(lockPath: string, ttlMs: number = 30000): Promise<boolean> {
  const lockDir = lockPath.endsWith('.lock') ? lockPath : `${lockPath}.lock`;

  try {
    await fs.mkdir(lockDir, { recursive: false });
    // Set TTL cleanup
    setTimeout(async () => {
      try {
        await fs.rm(lockDir, { recursive: true, force: true });
      } catch {
        // Ignore cleanup errors
      }
    }, ttlMs);
    return true;
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code === 'EEXIST') {
      return false; // Lock held by another process
    }
    throw new LockError(lockPath, `Failed to acquire lock: ${code}`);
  }
}

// FR-006: releaseLock(lockPath: string): Promise<void>
export async function releaseLock(lockPath: string): Promise<void> {
  const lockDir = lockPath.endsWith('.lock') ? lockPath : `${lockPath}.lock`;
  try {
    await fs.rm(lockDir, { recursive: true, force: true });
  } catch {
    // Idempotent - lock may not exist
  }
}

// FR-006: withLock<T>(lockPath: string, fn: () => Promise<T>): Promise<T>
export async function withLock<T>(lockPath: string, fn: () => Promise<T>): Promise<T> {
  const acquired = await acquireLock(lockPath);
  if (!acquired) {
    throw new LockError(lockPath, 'Could not acquire lock');
  }
  try {
    return await fn();
  } finally {
    await releaseLock(lockPath);
  }
}