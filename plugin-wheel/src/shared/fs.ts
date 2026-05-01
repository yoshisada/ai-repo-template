// FR-005: Filesystem helpers using fs/promises (no shell substitution)
import { promises as fs } from 'fs';
import path from 'path';
import { WheelError } from './error.js';
import { StateNotFoundError } from './error.js';

/**
 * Write content to path atomically: write to temp file, then rename.
 * FR-005: atomicWrite(path: string, content: string): Promise<void>
 */
export async function atomicWrite(targetPath: string, content: string): Promise<void> {
  const dir = path.dirname(targetPath);
  const tmpPath = path.join(dir, `.tmp.${Date.now()}.${Math.random().toString(36).slice(2)}`);

  try {
    await fs.writeFile(tmpPath, content, { encoding: 'utf-8' });
    try {
      await fs.rename(tmpPath, targetPath);
    } catch (renameErr) {
      // On Windows, rename fails if target exists; use writeFile + unlink approach
      try {
        await fs.unlink(targetPath);
      } catch {
        // Target didn't exist, ignore
      }
      await fs.rename(tmpPath, targetPath);
    }
  } catch (err) {
    try {
      await fs.unlink(tmpPath);
    } catch {
      // Ignore cleanup error
    }
    throw new WheelError('FS_WRITE', `Failed to write ${targetPath}`, { path: targetPath, cause: String(err) });
  }
}

/**
 * Recursively create directory and all ancestors. Idempotent.
 * FR-005: mkdirp(path: string): Promise<void>
 */
export async function mkdirp(dirPath: string): Promise<void> {
  try {
    await fs.mkdir(dirPath, { recursive: true });
  } catch (err) {
    // Ignore EEXIST (directory already exists)
    const code = (err as NodeJS.ErrnoException).code;
    if (code !== 'EEXIST') {
      throw new WheelError('FS_MKDIR', `Failed to create directory ${dirPath}`, { path: dirPath, cause: String(err) });
    }
  }
}

/**
 * Read file contents as string. Rejects if file does not exist.
 * FR-005: fileRead(path: string): Promise<string>
 */
export async function fileRead(filePath: string): Promise<string> {
  try {
    return await fs.readFile(filePath, { encoding: 'utf-8' });
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code === 'ENOENT') {
      throw new StateNotFoundError(filePath);
    }
    throw new WheelError('FS_READ', `Failed to read ${filePath}`, { path: filePath, cause: String(err) });
  }
}

/**
 * Check if a file exists (no throw on missing).
 * FR-005: fileExists(path: string): Promise<boolean>
 */
export async function fileExists(filePath: string): Promise<boolean> {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}