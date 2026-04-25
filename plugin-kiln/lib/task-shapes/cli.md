A `cli` task changes a command-line tool — argument parsing, stdout/stderr shape, exit
codes, help text. Substrate is direct subprocess invocation: pipe inputs, capture stdout
+ stderr separately, assert exit code, diff against golden output.

Report: exit code, stdout-diff outcome, stderr-diff outcome, and any tty-only behavior
observed (color codes, progress bars). Never claim a CLI is fixed on "it ran without
crashing" — the user-visible output shape is the contract. If the tool is interactive,
note that interactive paths cannot be tested in tier-2 substrate without `expect` or
similar harness; flag in the report.
