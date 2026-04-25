1..15
ok 1 WHEEL_PLUGIN token substitutes from registry
ok 2 WORKFLOW_PLUGIN_DIR substitutes against calling_plugin_dir (FR-F4-3)
ok 3 Multiple WHEEL_PLUGIN tokens in one instruction all substitute
ok 4 Plugin name with hyphen is supported by token grammar (I-P-2)
ok 5 Command steps are untouched (FR-F4-2 — only agent.instruction is preprocessed)
ok 6 Escaped $${WHEEL_PLUGIN_shelf} survives as literal ${WHEEL_PLUGIN_shelf}
ok 7 Escaped $${WORKFLOW_PLUGIN_DIR} survives as literal ${WORKFLOW_PLUGIN_DIR}
ok 8 Mixed escaped + unescaped tokens — escape preserved, real token substituted
ok 9 Calling template_workflow_json twice is a no-op on the second pass
ok 10 Idempotent when instruction has no plugin tokens at all
ok 11 Bash array iteration syntax ${files[@]} passes through unchanged
ok 12 Generic env var ${HOME} passes through unchanged (narrowed-pattern tripwire)
ok 13 Single-dollar $ outside braces passes through (no false positive)
ok 14 Workflow without requires_plugins and no plugin tokens is byte-identical
ok 15 Empty instruction is preserved unchanged
