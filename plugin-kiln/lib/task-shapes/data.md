A `data` task adds or migrates fixture corpora, schema definitions, or stored test
inputs. Substrate is round-trip validation: load → validate against schema → re-emit
→ assert byte-identical (or canonicalized-equivalent).

Report: schema validation result, count of fixtures added/changed, and an explicit
determinism assertion (re-running the load+emit pipeline produces byte-identical
output). Data work without a determinism check is a flake-magnet — every fixture
corpus must be pinned by checksum somewhere in the test suite.
