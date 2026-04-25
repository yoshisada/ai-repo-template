A `skill` task A/B-tests or modifies a Claude Code skill (a markdown command file under
`plugin-<name>/skills/<skill-name>/SKILL.md`). The substrate is `/kiln:kiln-test <plugin> <test>`,
which spawns real `claude --print --verbose --input-format=stream-json ... --plugin-dir`
subprocesses against `/tmp/kiln-test-<uuid>/` fixture directories.

Verdicts come from the watcher classifier (no hard timeouts — the classifier polls the
NDJSON transcript and decides healthy / stalled / failed). When you report results, cite:
exit code, last PASS/FAIL line from `run.sh`, scratch-dir path on failure, and any token
counts captured from the stream-json transcript. Never trust the prose your own subprocess
emits — trust only the substrate's exit code and the metrics extracted from the transcript.
