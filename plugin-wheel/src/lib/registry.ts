// FR-006: Cross-plugin registry for discovering plugin paths
import { promises as fs } from 'fs';
import path from 'path';

// FR-006: buildSessionRegistry(): Promise<SessionRegistry>
export async function buildSessionRegistry(): Promise<Record<string, string>> {
  const registry: Record<string, string> = {};
  const pluginCacheDir = path.join(process.env.HOME ?? '', '.claude', 'plugins', 'cache');

  try {
    const entries = await fs.readdir(pluginCacheDir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isDirectory()) {
        // Plugin dir format: org-plugin
        const parts = entry.name.split('-');
        if (parts.length >= 2) {
          // Use the last part as plugin name (e.g., "kiln" from "yoshisada-kiln")
          const pluginName = parts[parts.length - 1];
          registry[pluginName] = path.join(pluginCacheDir, entry.name);
        }
      }
    }
  } catch {
    // Plugin cache not available, return empty registry
  }

  return registry;
}

// FR-006: resolvePluginPath(pluginName: string, registry: SessionRegistry): string | null
export function resolvePluginPath(pluginName: string, registry: Record<string, string>): string | null {
  return registry[pluginName] ?? null;
}