---
id: 2026-04-24-wheel-per-step-model-selection
title: "Wheel per-step model selection for token optimization"
kind: feature
date: 2026-04-24
status: open
phase: unsorted
state: planned
blast_radius: cross-cutting
review_cost: moderate
context_cost: 2 sessions
implementation_hints: |
  Extend wheel workflow JSON schema to accept a `model` key on agent and team-dispatch steps.
  Value is a Claude model ID (e.g., "haiku-4-5-20251001", "sonnet-4-6", "opus-4-7") or a short alias.

  Schema change (agent step):
    {
      "id": "classify-description",
      "type": "agent",
      "model": "haiku-4-5-20251001",   // NEW — optional; default is inherit from parent
      "instruction": "...",
      ...
    }

  Schema change (team step — per-member model assignments already exist in some agent definitions
  via frontmatter, but the workflow JSON should be able to override):
    {
      "id": "implement",
      "type": "team",
      "members": [
        { "agent": "specifier",    "model": "opus-4-7" },
        { "agent": "test-runner",  "model": "haiku-4-5-20251001" }
      ]
    }

  Dispatch layer changes:
    - When wheel spawns an agent step, it passes `model:` through to the Agent tool call.
    - When a team step fires, each TaskCreate / Agent call respects its member's model override.
    - Missing `model` → inherit from parent session (current behavior).
    - Invalid model ID → fail the step with a clear error; don't silently downgrade.

  Token optimization goal: haiku for cheap classification / validation / retry steps;
  sonnet for standard reasoning; opus only for the hard long-context synthesis steps.
  A well-tuned workflow could cut total token cost significantly vs. running everything on opus.

  Validation: `validate-workflow.sh` should check the `model` field matches a known model ID pattern.
---

# Wheel per-step model selection for token optimization

## What

Extend the wheel workflow JSON schema so each agent step (and each member of a team step) can specify which Claude model it runs on. Today, every agent step inherits the parent session's model, which means cheap classification steps run on opus and burn tokens unnecessarily. Giving workflow authors per-step model control turns token optimization from a hope into a design decision.

## Why now

Wheel workflows are proliferating — kiln, shelf, clay, and trim each ship several. Most of their command-step work is cheap (read this file, validate this JSON) and most of their agent-step work is mixed (some steps need opus-level reasoning, most don't). Without per-step model selection, every workflow pays opus rates for haiku work. The pattern is now mature enough that hardcoding models at the step level is higher ROI than keeping everything inheritable.

## Assumptions

- The Agent tool already accepts a `model:` parameter on spawn (it does — `model: sonnet|opus|haiku` is in the current Agent schema).
- Wheel's dispatcher can read the `model` field from workflow JSON and pass it through when spawning.
- Workflow authors will want aliases (`haiku`, `sonnet`, `opus`) in addition to full model IDs — the harness already resolves both.
- A missing `model` field should fall back to parent-session inheritance so existing workflows keep working unchanged.

## Hardest part

Threading the model choice cleanly through the team-dispatch path. Team members are defined by agent frontmatter today, and some already pin a `model:` in the agent definition. The workflow-level override has to win when both are set, but in a way that doesn't break agents that rely on their frontmatter model for correctness (e.g., the haiku-only classifier agents). Clear precedence rule needed: workflow JSON > agent frontmatter > session default.

## Cheaper version

Ship agent-step `model` first (single-agent spawn path). Leave team-step per-member overrides for a follow-up — most token savings are in the cheap classification / validation agent steps, not in the team composition. Teams can keep using agent-frontmatter models until the full schema lands.

## Dependencies

- Depends on: Agent tool `model:` parameter (already ships in Claude Code).
- Depends on: wheel dispatcher being able to pass `model` through to Agent calls (may need runtime changes).
- Depends on: `validate-workflow.sh` being extended to recognize the new schema key.
