A `docs` task edits `README.md`, `CLAUDE.md`, spec docs, or rubric files. Substrate is
greppable assertions — fixture run.sh files that grep for canonical phrases the docs
must contain.

Report: every required phrase confirmed present (with line numbers), every removed
phrase confirmed absent, and the rubric (if any) the docs were audited against. Docs
work is load-bearing in this codebase because hooks + agents read CLAUDE.md content;
any ambiguity in phrasing leaks into agent behavior, so phrase-precise assertions are
the contract, not "a human reviewer thinks it reads well."
