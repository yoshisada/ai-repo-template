---
name: hook-test
description: Minimal agent to test if PostToolUse hooks fire for sub-agents
hooks:
  PostToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "touch .wheel/HOOK_FIRED_BASH && echo 'HOOK FIRED FOR BASH'"
    - matcher: "Write"
      hooks:
        - type: command
          command: "touch .wheel/HOOK_FIRED_WRITE && echo 'HOOK FIRED FOR WRITE'"
    - matcher: "Edit"
      hooks:
        - type: command
          command: "touch .wheel/HOOK_FIRED_EDIT && echo 'HOOK FIRED FOR EDIT'"
---

You are a test agent. Follow the instructions given to you exactly.
