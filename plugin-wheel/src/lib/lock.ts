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

// FR-007 (wheel-wait-all-redesign): Lock-ordering invariant — nothing in
// wheel takes a child state-file lock while holding a parent state-file
// lock. Concurrent teammate archives both need to update the parent's
// disjoint slots, so the lock must be retried with backoff rather than
// throw on contention. withLockBlocking acquires-or-waits up to timeoutMs
// with jittered backoff, then runs fn() and releases. Same lock semantics
// as withLock; only the contention behavior differs.
export async function withLockBlocking<T>(
  lockPath: string,
  fn: () => Promise<T>,
  timeoutMs: number = 5000
): Promise<T> {
  const start = Date.now();
  // FR-007: never hold two state-file locks at once. Caller is responsible
  // for releasing any prior lock BEFORE invoking this helper.
  while (true) {
    const acquired = await acquireLock(lockPath);
    if (acquired) {
      try {
        return await fn();
      } finally {
        await releaseLock(lockPath);
      }
    }
    if (Date.now() - start >= timeoutMs) {
      throw new LockError(
        lockPath,
        `Could not acquire lock within ${timeoutMs}ms`
      );
    }
    // Jittered backoff: 25–50 ms.
    await new Promise((r) => setTimeout(r, 25 + Math.random() * 25));
  }
}