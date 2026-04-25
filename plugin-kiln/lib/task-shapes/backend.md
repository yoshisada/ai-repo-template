A `backend` task touches server / API code — route handlers, business logic, database
queries, integration points. The substrate is `vitest run` (unit + integration) plus
real-binary E2E where applicable (Constitution V).

Report: vitest pass/fail, coverage percentage on new + changed lines (≥80% gate per
Constitution II), any integration suite results, and explicit confirmation that the
real binary was exercised (not just mocked). Surface load/latency/error-rate axes if
listed in the task spec — those come from a separate measurement step, not the unit
suite.
