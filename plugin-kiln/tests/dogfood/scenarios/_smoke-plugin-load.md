Harness smoke test. Do NOT run any workflow or skill. Only report availability.

Check your available Skill/slash commands and answer these two lines EXACTLY:

KILN: AVAILABLE if a skill named `kiln-next` (or `/kiln:kiln-next`) is in your
available skills, otherwise NOT_AVAILABLE.
SHELF: AVAILABLE if a skill named `shelf-status` (or `/shelf:shelf-status`) is in
your available skills, otherwise NOT_AVAILABLE.

Then write a file `proof.txt` in the current directory with exactly those two lines.
Then stop. No other output.
