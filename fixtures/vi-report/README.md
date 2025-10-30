# Compare report fixtures

Curated HTML/JSON snapshots that model minimal VI Comparison Report output for
unit testing. Each directory contains:

- `compare-report.html` – simplified single-file report stub with the headings
  and rows we want to validate.
- `lvcompare-capture.json` – minimal capture metadata pointing to the HTML.

The fixtures are intentionally lightweight (no embedded images) so tests can
parse the sections deterministically without invoking LVCompare.
