An `infra` task changes the wheel engine, hooks, build/install scripts, or other
tooling that other plugins depend on. Substrate is the wheel-test harness
(`/wheel:wheel-test`) plus targeted run.sh fixtures under
`plugin-wheel/tests/<feature>/run.sh`.

Report: every wheel-test workflow's pass/fail, every targeted fixture's exit code +
last-line PASS summary, and explicit confirmation that NO consumer-plugin behavior
regressed. Infra changes have the largest blast radius in this codebase — overshoot
on coverage, cite tripwire fixtures by name, and surface any silent-failure modes
discovered during work.
