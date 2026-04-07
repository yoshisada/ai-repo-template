---
name: wheel-create
description: Generate a wheel workflow JSON file from a natural language description or by reverse-engineering an existing file. Usage: /wheel-create <description> or /wheel-create from:<filepath>
---

# Wheel Create — Generate Workflow JSON

Create a new wheel workflow JSON file from either a natural language description or by reverse-engineering an existing file (SKILL.md, shell script, etc.).

**Two modes**:
- **Description Mode**: `/wheel-create gather git stats, analyze repo structure, write a health report`
- **File Mode**: `/wheel-create from:plugin-wheel/skills/wheel-status/SKILL.md`
