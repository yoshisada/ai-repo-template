# Shelf Tag Taxonomy

Canonical tag namespaces used across all shelf skills when creating or updating Obsidian notes. All tags follow the `namespace/value` convention.

## Source
Where the item originated.
- `source/github` — imported from a GitHub issue
- `source/backlog` — from `.kiln/issues/` backlog
- `source/retro` — from a pipeline retrospective
- `source/manual` — user-reported directly

## Severity
Priority level of issues.
- `severity/critical` — blocks work, needs immediate fix
- `severity/high` — important, should be addressed soon
- `severity/medium` — standard priority
- `severity/low` — nice-to-have, no urgency

## Type
Classification of issues.
- `type/bug` — broken behavior
- `type/friction` — works but painful
- `type/improvement` — enhancement to existing functionality
- `type/feature-request` — net-new capability
- `type/retrospective` — pipeline retrospective finding

## Category
Which part of the system is affected.
- `category/skills` — skill behavior, prompts, flow
- `category/agents` — agent definitions, team structure
- `category/hooks` — enforcement rules
- `category/templates` — spec/plan/task templates
- `category/scaffold` — init script, project structure
- `category/workflow` — pipeline, build-prd orchestration

## Doc Type
Classification of documentation notes.
- `doc/prd` — product requirements document
- `doc/spec` — feature specification
- `doc/plan` — implementation plan
- `doc/overview` — project-level overview
- `doc/decision` — architectural decision record

## Status
Current state of the item.
- `status/open` — active, needs attention
- `status/closed` — resolved or completed
- `status/implemented` — feature has been built
- `status/in-progress` — currently being worked on

## Language
Programming languages detected in the project.
- `language/javascript` — JavaScript (from package.json without TypeScript)
- `language/typescript` — TypeScript (from tsconfig.json or TypeScript dependency)
- `language/rust` — Rust (from Cargo.toml)
- `language/python` — Python (from pyproject.toml or requirements.txt)
- `language/go` — Go (from go.mod)
- `language/ruby` — Ruby (from Gemfile)

## Framework
Frameworks and libraries detected in the project.
- `framework/react` — React (from package.json dependencies)
- `framework/next` — Next.js (from package.json dependencies)
- `framework/vue` — Vue.js (from package.json dependencies)
- `framework/express` — Express (from package.json dependencies)
- `framework/fastify` — Fastify (from package.json dependencies)

## Infrastructure
Infrastructure and CI/CD tools detected in the project.
- `infra/docker` — Docker (from Dockerfile or docker-compose.yml)
- `infra/github-actions` — GitHub Actions (from .github/workflows/)

## Usage

All shelf skills that create or update Obsidian notes MUST:
1. Read this taxonomy to determine valid tags
2. Apply tags from the appropriate namespaces based on note type and content
3. Include `project: "[[{slug}]]"` as a backlink in every note's frontmatter
4. Never invent tags outside these namespaces without updating this file first
