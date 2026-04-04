#!/usr/bin/env node

/**
 * wheel init — FR-016
 *
 * Scaffolds the wheel workflow engine into the current directory.
 * Creates .wheel/, workflows/, and merges hook configuration into
 * .claude/settings.json.
 *
 * Safe to run multiple times (idempotent) — existing files are not
 * overwritten unless --force is passed.
 *
 * Usage:
 *   npx @yoshisada/wheel init [--force]
 *   npx @yoshisada/wheel update
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync, copyFileSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = resolve(__dirname, "..");
const PROJECT_DIR = process.cwd();

const args = process.argv.slice(2);
const command = args[0] || "init";
const force = args.includes("--force");

function log(msg) {
  console.log(`  ${msg}`);
}

function ensureDir(dir) {
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
}

function copyIfMissing(src, dest, description) {
  if (existsSync(dest) && !force) {
    log(`ok ${description} (exists)`);
    return false;
  }
  ensureDir(dirname(dest));
  copyFileSync(src, dest);
  log(`+  ${description}`);
  return true;
}

// FR-016: Initialize wheel in a consumer project
// Creates .wheel/, workflows/, merges hooks into .claude/settings.json
export async function init(targetDir) {
  const dir = targetDir || PROJECT_DIR;

  console.log("\n--- wheel init ---\n");

  // .wheel/ runtime directory
  ensureDir(join(dir, ".wheel"));
  ensureDir(join(dir, ".wheel", ".locks"));
  log("+  .wheel/ (runtime state directory)");

  // workflows/ directory
  ensureDir(join(dir, "workflows"));
  log("+  workflows/ (workflow definitions)");

  // Copy example workflow
  copyIfMissing(
    join(PLUGIN_ROOT, "scaffold", "example-workflow.json"),
    join(dir, "workflows", "example.json"),
    "workflows/example.json (example 3-step workflow)"
  );

  // Add .wheel/ entries to .gitignore
  const gitignorePath = join(dir, ".gitignore");
  let gitignore = "";
  if (existsSync(gitignorePath)) {
    gitignore = readFileSync(gitignorePath, "utf8");
  }
  const ignoreEntries = [".wheel/state.json", ".wheel/.locks/"];
  let modified = false;
  for (const entry of ignoreEntries) {
    if (!gitignore.includes(entry)) {
      gitignore += `\n${entry}`;
      modified = true;
    }
  }
  if (modified) {
    writeFileSync(gitignorePath, gitignore.trimEnd() + "\n");
    log("+  .gitignore (added .wheel/ entries)");
  } else {
    log("ok .gitignore (.wheel/ entries exist)");
  }

  // Merge hook configuration into .claude/settings.json
  mergeHookSettings(dir);

  // Verify
  verify(dir);
}

// FR-016: Update wheel scaffold in an existing consumer project
// Re-syncs hook scripts and settings without overwriting user workflows
export async function update(targetDir) {
  const dir = targetDir || PROJECT_DIR;

  console.log("\n--- wheel update ---\n");

  // Re-merge hook settings (in case plugin updated hook paths)
  mergeHookSettings(dir);

  log("ok Wheel settings synced to latest.");
  console.log("");
}

function mergeHookSettings(dir) {
  const settingsDir = join(dir, ".claude");
  ensureDir(settingsDir);

  const settingsPath = join(settingsDir, "settings.json");
  let settings = {};
  if (existsSync(settingsPath)) {
    try {
      settings = JSON.parse(readFileSync(settingsPath, "utf8"));
    } catch {
      log("!! .claude/settings.json exists but is invalid JSON — backing up and recreating");
      copyFileSync(settingsPath, settingsPath + ".bak");
      settings = {};
    }
  }

  // Load the hook configuration template
  const hooksConfig = JSON.parse(
    readFileSync(join(PLUGIN_ROOT, "scaffold", "settings-hooks.json"), "utf8")
  );

  // Merge hooks — add wheel hooks without removing existing ones
  if (!settings.hooks) {
    settings.hooks = {};
  }

  for (const [event, entries] of Object.entries(hooksConfig.hooks)) {
    if (!settings.hooks[event]) {
      settings.hooks[event] = [];
    }
    for (const entry of entries) {
      // Check if this exact hook command already exists
      const exists = settings.hooks[event].some(
        (existing) =>
          existing.hooks &&
          existing.hooks.some(
            (h) => entry.hooks && entry.hooks.some((e) => h.command === e.command)
          )
      );
      if (!exists) {
        settings.hooks[event].push(entry);
      }
    }
  }

  writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
  log("+  .claude/settings.json (wheel hooks merged)");
}

function verify(dir) {
  console.log("\nVerifying...\n");

  const checks = [
    [".wheel", "Runtime state directory"],
    ["workflows", "Workflow definitions directory"],
    ["workflows/example.json", "Example workflow"],
    [".claude/settings.json", "Hook configuration"],
  ];

  let passed = 0;
  for (const [path, label] of checks) {
    if (existsSync(join(dir, path))) {
      log(`ok ${label}`);
      passed++;
    } else {
      log(`!! ${label} -- missing: ${path}`);
    }
  }

  // Check plugin reachable
  const pluginJson = join(PLUGIN_ROOT, ".claude-plugin", "plugin.json");
  if (existsSync(pluginJson)) {
    log("ok wheel plugin (installed)");
    passed++;
  } else {
    log("!! wheel plugin -- not found");
  }

  const total = checks.length + 1;
  console.log("");
  if (passed === total) {
    console.log(`All ${total} checks passed. Wheel is ready.\n`);
  } else {
    console.log(`${passed}/${total} checks passed. Some items need attention.\n`);
  }

  console.log("Next steps:");
  console.log("  1. Create a workflow definition in workflows/");
  console.log("  2. Start a Claude Code session to run it");
  console.log("");
}

// ── Main ──

switch (command) {
  case "init":
    await init();
    break;
  case "update":
    await update();
    break;
  default:
    console.log("Usage: wheel <init|update> [--force]");
    console.log("");
    console.log("  init     Scaffold wheel workflow engine into the current project");
    console.log("  update   Re-sync hook configuration to latest plugin version");
    console.log("  --force  Overwrite existing files (use with caution)");
    process.exit(1);
}
