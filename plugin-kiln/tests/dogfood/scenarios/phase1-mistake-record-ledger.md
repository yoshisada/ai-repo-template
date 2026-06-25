You are testing the kiln Phase 1 precedent ledger. The current directory is an empty git
repo. You are HEADLESS — pick defaults, never wait for input. Be concise.

Do these steps in order:

1. Initialize kiln so the .kiln/ directory structure (including .kiln/ledger/) exists. Run
   `/kiln:kiln-init` non-interactively (skip the vision interview; accept defaults). If
   kiln-init stalls on interaction, instead just create the dirs directly:
   `mkdir -p .kiln/ledger .kiln/ledger/proposals .kiln/mistakes .wheel/inputs .wheel/outputs`.

2. Write a sample mistake input to `.wheel/inputs/mistake-data.json` with EXACTLY this content:
   {"summary":"Assumed wheel supports model_tier","assumption":"I assumed wheel resolves a model_tier field against config.json","correction":"Wheel only honors a concrete model field; tiers do not exist in the runtime","source":"report-issue"}

3. Run the kiln-mistake-record workflow to record it:
   `/wheel:wheel-run kiln:kiln-mistake-record`
   Let it run to completion. If wheel-run is unavailable or errors, report that clearly and
   then MANUALLY perform what the workflow's write-mistake step specifies (read
   plugin source if needed) so the ledger files still get produced — note that you fell back.

4. Inspect the results on disk and report.

5. Run `/kiln:kiln-ledger` to list the ledger and capture its table output.

Report EXACTLY this, filling in real values:

```
=== PHASE 1 MISTAKE-RECORD DOGFOOD ===
ran via:               workflow | manual-fallback
mistake .md created:   yes|no  (path: ___)
ledger .json created:  yes|no  (path: ___)
ledger id format:      <the actual id>   (expected shape: YYYY-MM-DD-<slug>)
ledger entry kind:     <value of .kind>
ledger entry tags:     <the tags array>
ledger schema fields:  <comma-list of top-level keys in the .json>
kiln-ledger output:    <paste the table or "empty" message>
obsidian sync:         <what the sync-to-obsidian step reported — likely synced:false, no .shelf-config>
notes:                 <anything broken, any field missing vs schema id,kind,summary,detail,blast_radius,tags,source_path,ts>
```

Keep total output under 70 lines.
