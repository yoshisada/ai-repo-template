// Scenario: S2 — jqQuery extracts values by path, throws on invalid
import { describe, it, expect } from 'vitest';
import { jqQuery, jqQueryRaw, jqUpdate } from './jq.js';
import { ValidationError } from './error.js';

describe('jqQuery', () => {
  it('should extract string at simple path', () => { // FR-005
    const obj = { name: 'test', status: 'running' };
    expect(jqQuery<string>(obj, '.name')).toBe('test');
  });

  it('should extract nested object', () => { // FR-005
    const obj = { user: { name: 'Alice', age: 30 } };
    const result = jqQuery<{ name: string; age: number }>(obj, '.user');
    expect(result.name).toBe('Alice');
    expect(result.age).toBe(30);
  });

  it('should extract array element', () => { // FR-005
    const obj = { steps: [{ id: 's1' }, { id: 's2' }] };
    expect(jqQuery<string>(obj, '.steps[0].id')).toBe('s1');
  });

  it('should throw ValidationError for invalid path', () => { // FR-005
    const obj = { name: 'test' };
    expect(() => jqQuery(obj, '.nonexistent')).toThrow(ValidationError);
  });

  it('should throw for null result', () => { // FR-005
    const obj = { foo: null };
    expect(() => jqQuery(obj, '.foo')).toThrow(ValidationError);
  });
});

describe('jqQueryRaw', () => {
  it('should return raw JSON string', () => { // FR-005
    const obj = { count: 42 };
    expect(jqQueryRaw(obj, '.count')).toBe('42');
  });

  it('should return object as JSON string', () => { // FR-005
    const obj = { nested: { value: true } };
    expect(jqQueryRaw(obj, '.nested')).toBe('{"value":true}');
  });
});

describe('jqUpdate', () => {
  it('should update simple field', () => { // FR-005
    const obj = { status: 'pending', name: 'test' };
    const result = JSON.parse(jqUpdate(obj, '.status', 'done'));
    expect(result.status).toBe('done');
    expect(result.name).toBe('test');
  });

  it('should update nested field', () => { // FR-005
    const obj = { config: { timeout: 30 } };
    const result = JSON.parse(jqUpdate(obj, '.config.timeout', 60));
    expect(result.config.timeout).toBe(60);
  });

  it('should update array element', () => { // FR-005
    const obj = { steps: [{ status: 'pending' }, { status: 'pending' }] };
    const result = JSON.parse(jqUpdate(obj, '.steps[0].status', 'done'));
    expect(result.steps[0].status).toBe('done');
    expect(result.steps[1].status).toBe('pending');
  });

  it('should throw ValidationError for invalid array index path', () => { // FR-005
    const obj = { steps: [] };
    expect(() => jqUpdate(obj, '.steps[99].status', 'done')).toThrow(ValidationError);
  });

  it('should allow creating new property on object', () => { // FR-005
    const obj = { name: 'test' };
    const result = JSON.parse(jqUpdate(obj, '.newProp', 'value'));
    expect(result.newProp).toBe('value');
    expect(result.name).toBe('test');
  });
});