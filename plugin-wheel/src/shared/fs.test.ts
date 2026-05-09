// Scenario: S3 — atomicWrite, mkdirp, fileRead, fileExists work correctly
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { promises as fs } from 'fs';
import path from 'path';
import { atomicWrite, mkdirp, fileRead, fileExists } from './fs.js';
import { StateNotFoundError } from './error.js';

const TEST_DIR = '/tmp/wheel-fs-test';

beforeEach(async () => {
  await fs.mkdir(TEST_DIR, { recursive: true });
});

afterEach(async () => {
  await fs.rm(TEST_DIR, { recursive: true, force: true });
});

describe('atomicWrite', () => {
  it('should write file atomically', async () => { // FR-005
    const targetPath = path.join(TEST_DIR, 'test.txt');
    await atomicWrite(targetPath, 'hello world');
    const content = await fs.readFile(targetPath, 'utf-8');
    expect(content).toBe('hello world');
  });

  it('should overwrite existing file', async () => { // FR-005
    const targetPath = path.join(TEST_DIR, 'overwrite.txt');
    await atomicWrite(targetPath, 'first');
    await atomicWrite(targetPath, 'second');
    const content = await fs.readFile(targetPath, 'utf-8');
    expect(content).toBe('second');
  });
});

describe('mkdirp', () => {
  it('should create nested directories', async () => { // FR-005
    const nested = path.join(TEST_DIR, 'a', 'b', 'c');
    await mkdirp(nested);
    const stat = await fs.stat(nested);
    expect(stat.isDirectory()).toBe(true);
  });

  it('should be idempotent', async () => { // FR-005
    const nested = path.join(TEST_DIR, 'x', 'y');
    await mkdirp(nested);
    await mkdirp(nested); // Should not throw
    const stat = await fs.stat(nested);
    expect(stat.isDirectory()).toBe(true);
  });
});

describe('fileRead', () => {
  it('should read file contents', async () => { // FR-005
    const filePath = path.join(TEST_DIR, 'read.txt');
    await fs.writeFile(filePath, 'file content');
    const content = await fileRead(filePath);
    expect(content).toBe('file content');
  });

  it('should throw StateNotFoundError for missing file', async () => { // FR-005
    const missing = path.join(TEST_DIR, 'nonexistent.txt');
    await expect(fileRead(missing)).rejects.toThrow(StateNotFoundError);
  });
});

describe('fileExists', () => {
  it('should return true for existing file', async () => { // FR-005
    const filePath = path.join(TEST_DIR, 'exists.txt');
    await fs.writeFile(filePath, 'data');
    const exists = await fileExists(filePath);
    expect(exists).toBe(true);
  });

  it('should return false for missing file', async () => { // FR-005
    const missing = path.join(TEST_DIR, 'missing.txt');
    const exists = await fileExists(missing);
    expect(exists).toBe(false);
  });
});