// FR-005: Pure TypeScript jq path query (no jq CLI dependency)
import { ValidationError } from './error.js';

/**
 * Evaluate a jq path expression against json and return the result cast to T.
 * FR-005: jqQuery<T>(json: unknown, path: string): T
 */
export function jqQuery<T>(json: unknown, path: string): T {
  const result = jqQueryRaw(json, path);
  if (result === 'null') {
    throw new ValidationError(path, 'path evaluates to null');
  }
  try {
    return JSON.parse(result) as T;
  } catch {
    // Return as string for literal jq outputs (e.g., ".foo" on string returns "bar")
    return result as unknown as T;
  }
}

/**
 * Same as jqQuery but returns the raw JSON string representation.
 * FR-005: jqQueryRaw(json: unknown, path: string): string
 */
export function jqQueryRaw(json: unknown, path: string): string {
  // Strip leading dot if present (jq paths start with '.')
  const cleanPath = path.startsWith('.') ? path.slice(1) : path;
  const segments = cleanPath.split('.').filter(s => s.length > 0);

  let current: unknown = json;
  for (const seg of segments) {
    if (current === null || current === undefined) {
      throw new ValidationError(path, `null/undefined at segment '${seg}'`);
    }

    if (Array.isArray(current)) {
      // Handle array index like [0] or steps[0]
      const arrayMatch = seg.match(/^(\w+)\[(\d+)\]$/);
      if (arrayMatch) {
        const idx = parseInt(arrayMatch[2], 10);
        if (idx >= 0 && idx < (current as unknown[]).length) {
          current = (current as unknown[])[idx];
        } else {
          throw new ValidationError(path, `array index ${idx} out of bounds`);
        }
      } else {
        throw new ValidationError(path, `cannot index array with '${seg}'`);
      }
    } else if (typeof current === 'object' && current !== null) {
      // Object property access
      const arrayMatch = seg.match(/^(\w+)\[(\d+)\]$/);
      if (arrayMatch) {
        const key = arrayMatch[1];
        const idx = parseInt(arrayMatch[2], 10);
        const arr = (current as Record<string, unknown>)[key];
        if (Array.isArray(arr)) {
          if (idx >= 0 && idx < arr.length) {
            current = arr[idx];
          } else {
            throw new ValidationError(path, `array index ${idx} out of bounds for key '${key}'`);
          }
        } else {
          throw new ValidationError(path, `key '${key}' is not an array`);
        }
      } else {
        current = (current as Record<string, unknown>)[seg];
      }
    } else {
      throw new ValidationError(path, `cannot traverse ${typeof current} at segment '${seg}'`);
    }
  }

  if (current === undefined) {
    throw new ValidationError(path, 'path evaluates to undefined');
  }

  return JSON.stringify(current);
}

/**
 * Return a new JSON string with value assigned at the jq path.
 * FR-005: jqUpdate(json: unknown, path: string, value: unknown): string
 */
export function jqUpdate(json: unknown, path: string, value: unknown): string {
  const cleanPath = path.startsWith('.') ? path.slice(1) : path;
  const segments = cleanPath.split('.').filter(s => s.length > 0);

  if (segments.length === 0) {
    return JSON.stringify(value);
  }

  // Deep clone the JSON
  const result = JSON.parse(JSON.stringify(json));
  let current: unknown = result;

  for (let i = 0; i < segments.length - 1; i++) {
    const seg = segments[i];
    const arrayMatch = seg.match(/^(\w+)\[(\d+)\]$/);

    if (Array.isArray(current)) {
      if (arrayMatch) {
        const idx = parseInt(arrayMatch[2], 10);
        if (idx >= 0 && idx < (current as unknown[]).length) {
          current = (current as unknown[])[idx];
        } else {
          throw new ValidationError(path, `array index ${idx} out of bounds`);
        }
      }
    } else if (typeof current === 'object' && current !== null) {
      if (arrayMatch) {
        const key = arrayMatch[1];
        const idx = parseInt(arrayMatch[2], 10);
        const arr = (current as Record<string, unknown>)[key];
        if (!Array.isArray(arr)) {
          throw new ValidationError(path, `key '${key}' is not an array`);
        }
        if (idx >= 0 && idx < arr.length) {
          current = arr[idx];
        } else {
          throw new ValidationError(path, `array index ${idx} out of bounds`);
        }
      } else {
        current = (current as Record<string, unknown>)[seg];
      }
    }

    if (current === undefined) {
      throw new ValidationError(path, `cannot traverse to segment '${seg}'`);
    }
  }

  // Set the final segment - must validate target exists or is creatable
  const lastSeg = segments[segments.length - 1];
  const lastArrayMatch = lastSeg.match(/^(\w+)\[(\d+)\]$/);

  if (Array.isArray(current)) {
    if (lastArrayMatch) {
      const idx = parseInt(lastArrayMatch[2], 10);
      if (idx >= 0 && idx < (current as unknown[]).length) {
        (current as unknown[])[idx] = value;
      } else {
        throw new ValidationError(path, `array index ${idx} out of bounds`);
      }
    } else {
      throw new ValidationError(path, `cannot set index '${lastSeg}' on array`);
    }
  } else if (typeof current === 'object' && current !== null) {
    if (lastArrayMatch) {
      const key = lastArrayMatch[1];
      const idx = parseInt(lastArrayMatch[2], 10);
      const arr = (current as Record<string, unknown>)[key];
      if (!Array.isArray(arr)) {
        throw new ValidationError(path, `key '${key}' is not an array`);
      }
      if (idx >= 0 && idx < arr.length) {
        arr[idx] = value;
      } else {
        throw new ValidationError(path, `array index ${idx} out of bounds`);
      }
    } else {
      // For object property, jq allows creating new properties
      // But per contract: "Throws ValidationError if path is not an lvalue"
      // We allow creation for nested paths, but for direct property assignment
      // we validate the parent structure exists
      (current as Record<string, unknown>)[lastSeg] = value;
    }
  } else {
    throw new ValidationError(path, `cannot set property on ${typeof current}`);
  }

  return JSON.stringify(result);
}