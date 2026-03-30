#!/usr/bin/env node

/**
 * speckit-harness init
 *
 * Scaffolds the spec-first development infrastructure into the current directory.
 * Safe to run multiple times (idempotent) — existing files are not overwritten
 * unless --force is passed.
 *
 * When installed as a Claude Code plugin, skills/agents/hooks are auto-discovered
 * from the plugin directory. This script only creates project-specific files
 * (CLAUDE.md, constitution, PRD, directory structure, templates).
 *
 * Usage:
 *   npx @yoshisada/speckit-harness init [--force]
 *   npx @yoshisada/speckit-harness update     # re-sync templates to latest
 */

import { existsSync, mkdirSync, cpSync, writeFileSync, copyFileSync } from "node:fs";
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
    log(`✓ ${description} (exists)`);
    return false;
  }
  ensureDir(dirname(dest));
  copyFileSync(src, dest);
  log(`+ ${description}`);
  return true;
}

function syncDir(src, dest, description) {
  ensureDir(dirname(dest));
  cpSync(src, dest, { recursive: true, force: true });
  log(`↻ ${description}`);
}

// ── Scaffold: project-specific files (only on init, never overwrite) ──

function scaffoldProject() {
  console.log("\n╭─────────────────────────────────────╮");
  console.log("│  speckit-harness — init              │");
  console.log("╰─────────────────────────────────────╯\n");

  const scaffold = join(PLUGIN_ROOT, "scaffold");

  // Core files
  copyIfMissing(join(scaffold, "CLAUDE.md"), join(PROJECT_DIR, "CLAUDE.md"), "CLAUDE.md (workflow rules)");
  copyIfMissing(join(scaffold, "gitignore"), join(PROJECT_DIR, ".gitignore"), ".gitignore");

  // Docs
  ensureDir(join(PROJECT_DIR, "docs"));
  copyIfMissing(join(scaffold, "docs", "PRD.md"), join(PROJECT_DIR, "docs", "PRD.md"), "docs/PRD.md (template)");
  copyIfMissing(join(scaffold, "docs", "session-prompt.md"), join(PROJECT_DIR, "docs", "session-prompt.md"), "docs/session-prompt.md");

  // Specs
  ensureDir(join(PROJECT_DIR, "specs"));
  copyIfMissing(join(scaffold, "specs", "README.md"), join(PROJECT_DIR, "specs", "README.md"), "specs/README.md");

  // Speckit memory
  ensureDir(join(PROJECT_DIR, ".specify", "memory"));
  copyIfMissing(
    join(scaffold, "constitution.md"),
    join(PROJECT_DIR, ".specify", "memory", "constitution.md"),
    ".specify/memory/constitution.md"
  );

  // Empty directories
  for (const dir of ["src", "tests"]) {
    ensureDir(join(PROJECT_DIR, dir));
    const gitkeep = join(PROJECT_DIR, dir, ".gitkeep");
    if (!existsSync(gitkeep)) {
      writeFileSync(gitkeep, "");
      log(`+ ${dir}/.gitkeep`);
    }
  }
}

// ── Sync: shared infrastructure (always update to latest) ──

function syncShared() {
  if (command === "init") {
    console.log("\nSyncing shared infrastructure...\n");
  } else {
    console.log("\n╭─────────────────────────────────────╮");
    console.log("│  speckit-harness — update            │");
    console.log("╰─────────────────────────────────────╯\n");
  }

  // Templates — always sync to latest
  syncDir(join(PLUGIN_ROOT, "templates"), join(PROJECT_DIR, ".specify", "templates"), ".specify/templates/");

  // Speckit scripts
  if (existsSync(join(PLUGIN_ROOT, "scaffold", "specify-scripts"))) {
    syncDir(
      join(PLUGIN_ROOT, "scaffold", "specify-scripts"),
      join(PROJECT_DIR, ".specify", "scripts"),
      ".specify/scripts/"
    );
  }

  // Note: skills, agents, and hooks are auto-discovered by Claude Code
  // from the plugin directory. No need to copy them into the project.
  log("✓ Skills, agents, hooks provided by plugin (auto-discovered)");
}

// ── Verify ──

function verify() {
  console.log("\nVerifying...\n");
  const checks = [
    ["CLAUDE.md", "Workflow rules"],
    [".specify/memory/constitution.md", "Constitution"],
    [".specify/templates/spec-template.md", "Spec template"],
    ["docs/PRD.md", "PRD placeholder"],
    ["specs/README.md", "Specs directory"],
  ];

  let passed = 0;
  for (const [path, label] of checks) {
    if (existsSync(join(PROJECT_DIR, path))) {
      log(`✓ ${label}`);
      passed++;
    } else {
      log(`✗ ${label} — missing: ${path}`);
    }
  }

  // Check plugin is reachable
  const pluginJson = join(PLUGIN_ROOT, ".claude-plugin", "plugin.json");
  if (existsSync(pluginJson)) {
    log("✓ speckit-harness plugin (installed)");
    passed++;
  } else {
    log("✗ speckit-harness plugin — not found");
  }
  const total = checks.length + 1;

  console.log("");
  if (passed === total) {
    console.log(`✓ All ${total} checks passed — setup complete!\n`);
  } else {
    console.log(`✗ ${passed}/${total} checks passed — some items need attention.\n`);
  }

  console.log("Next steps:");
  console.log("  1. Edit docs/PRD.md with your product requirements (or run /speckit-harness:create-prd)");
  console.log("  2. Run /speckit-harness:build-prd to start building");
  console.log("");
}

// ── Main ──

switch (command) {
  case "init":
    scaffoldProject();
    syncShared();
    verify();
    break;
  case "update":
    syncShared();
    console.log("\n✓ Shared infrastructure updated to latest.\n");
    break;
  default:
    console.log("Usage: speckit-harness <init|update> [--force]");
    console.log("");
    console.log("  init     Scaffold a new project with spec-first infrastructure");
    console.log("  update   Re-sync templates to latest plugin version");
    console.log("  --force  Overwrite existing project files (use with caution)");
    process.exit(1);
}
