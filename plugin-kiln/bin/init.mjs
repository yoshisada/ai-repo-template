#!/usr/bin/env node

/**
 * kiln init
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
 *   npx @yoshisada/kiln init [--force]
 *   npx @yoshisada/kiln update     # re-sync templates to latest
 */

import { existsSync, mkdirSync, cpSync, writeFileSync, copyFileSync, readdirSync } from "node:fs";
import { resolve, dirname, join, basename } from "node:path";
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
  console.log("│  kiln — init              │");
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

  // Kiln memory
  ensureDir(join(PROJECT_DIR, ".specify", "memory"));
  copyIfMissing(
    join(scaffold, "constitution.md"),
    join(PROJECT_DIR, ".specify", "memory", "constitution.md"),
    ".specify/memory/constitution.md"
  );

  // Version tracking
  const versionFile = join(PROJECT_DIR, "VERSION");
  if (!existsSync(versionFile) || force) {
    writeFileSync(versionFile, "000.000.000.000\n");
    log("+ VERSION (000.000.000.000)");
  } else {
    log(`✓ VERSION (exists)`);
  }

  // Scripts directory
  ensureDir(join(PROJECT_DIR, "scripts"));
  copyIfMissing(
    join(PLUGIN_ROOT, "hooks", "version-increment.sh"),
    join(PROJECT_DIR, "scripts", "version-increment.sh"),
    "scripts/version-increment.sh (auto-increment hook)"
  );

  // .kiln/ directory structure (FR-008, FR-009)
  // FR-007: QA subdirectories created during scaffold
  const kilnDirs = [
    ".kiln/workflows",
    ".kiln/agents",
    ".kiln/issues",
    ".kiln/issues/completed",  // FR-024: archival directory for closed/done issues
    ".kiln/templates",         // FR-019: consumer-customizable templates
    ".kiln/qa",
    ".kiln/qa/tests",
    ".kiln/qa/results",
    ".kiln/qa/screenshots",
    ".kiln/qa/videos",
    ".kiln/qa/config",
    ".kiln/logs",
    ".kiln/ledger",              // Phase 1: precedent ledger entries
    ".kiln/ledger/proposals"     // Phase 1: improvement proposals derived from ledger
  ];
  for (const dir of kilnDirs) {
    ensureDir(join(PROJECT_DIR, dir));
    log(`+ ${dir}/`);
  }

  // FR-008: Copy QA README template
  copyIfMissing(
    join(scaffold, "qa-readme.md"),
    join(PROJECT_DIR, ".kiln", "qa", "README.md"),
    ".kiln/qa/README.md"
  );

  // FR-019: Scaffold issue template into consumer project for customization
  copyIfMissing(
    join(PLUGIN_ROOT, "templates", "issue.md"),
    join(PROJECT_DIR, ".kiln", "templates", "issue.md"),
    ".kiln/templates/issue.md (issue template)"
  );

  // FR-014: Scaffold roadmap into consumer project
  copyIfMissing(
    join(PLUGIN_ROOT, "templates", "roadmap-template.md"),
    join(PROJECT_DIR, ".kiln", "roadmap.md"),
    ".kiln/roadmap.md (roadmap)"
  );

  // Phase 0 (kiln-autonomous): config foundation. Defaults the consumer can edit;
  // the kiln-init wizard customizes review_mode / design_first / branching after.
  // doctor-manifest.json is intentionally NOT copied — kiln-doctor reads it from the
  // plugin install path so new version entries ship without touching consumers.
  copyIfMissing(
    join(scaffold, "config-template.json"),
    join(PROJECT_DIR, ".kiln", "config.json"),
    ".kiln/config.json (review + standards + model config)"
  );
  copyIfMissing(
    join(scaffold, "standards-template.md"),
    join(PROJECT_DIR, ".kiln", "standards.md"),
    ".kiln/standards.md (coding standards)"
  );
  copyIfMissing(
    join(scaffold, "test-strategy-template.json"),
    join(PROJECT_DIR, ".kiln", "test-strategy.json"),
    ".kiln/test-strategy.json (coverage gate + smoke config)"
  );
}

// ── Sync: plugin workflows to consumer project (FR-002) ──

function syncWorkflows() {
  // Discover workflows by filesystem scan, not a plugin.json field. The manifest
  // `workflows` array is non-standard (it fails `claude plugin validate`, which in
  // turn blocks the plugin's skills from loading under --plugin-dir) and redundant —
  // wheel discovers workflows from the plugin's workflows/ dir, matching the
  // filesystem-backed-discovery vision constraint.
  const workflowsSrc = join(PLUGIN_ROOT, "workflows");
  if (!existsSync(workflowsSrc)) return;

  const files = readdirSync(workflowsSrc).filter((f) => f.endsWith(".json"));
  if (files.length === 0) return;

  ensureDir(join(PROJECT_DIR, "workflows"));
  for (const f of files) {
    copyIfMissing(join(workflowsSrc, f), join(PROJECT_DIR, "workflows", f), `workflows/${f}`);
  }
}

// ── Sync: shared infrastructure (always update to latest) ──

function syncShared() {
  if (command === "init") {
    console.log("\nSyncing shared infrastructure...\n");
  } else {
    console.log("\n╭─────────────────────────────────────╮");
    console.log("│  kiln — update            │");
    console.log("╰─────────────────────────────────────╯\n");
  }

  // Templates — always sync to latest
  syncDir(join(PLUGIN_ROOT, "templates"), join(PROJECT_DIR, ".specify", "templates"), ".specify/templates/");

  // Kiln scripts
  if (existsSync(join(PLUGIN_ROOT, "scaffold", "specify-scripts"))) {
    syncDir(
      join(PLUGIN_ROOT, "scaffold", "specify-scripts"),
      join(PROJECT_DIR, ".specify", "scripts"),
      ".specify/scripts/"
    );
  }

  // FR-002: Sync plugin workflows to consumer project
  syncWorkflows();

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
    ["VERSION", "Version tracking"],
    [".kiln/workflows", ".kiln/ directory"],
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
    log("✓ kiln plugin (installed)");
    passed++;
  } else {
    log("✗ kiln plugin — not found");
  }
  const total = checks.length + 1;

  console.log("");
  if (passed === total) {
    console.log(`✓ All ${total} checks passed — setup complete!\n`);
  } else {
    console.log(`✗ ${passed}/${total} checks passed — some items need attention.\n`);
  }

  console.log("Next steps:");
  console.log("  1. Edit docs/PRD.md with your product requirements (or run /kiln:create-prd)");
  console.log("  2. Run /kiln:build-prd to start building");
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
    console.log("Usage: kiln <init|update> [--force]");
    console.log("");
    console.log("  init     Scaffold a new project with spec-first infrastructure");
    console.log("  update   Re-sync templates to latest plugin version");
    console.log("  --force  Overwrite existing project files (use with caution)");
    process.exit(1);
}
