# AGENTS.md - health-charts.el

Standalone, publishable Emacs package: medical and health charts (vitals,
labs, glucose, medication, sleep, growth, ...) as text or SVG from data the
caller supplies, validated strictly and drawn by eas templates. It never
fetches or supplies data. README.md is the full reference.

`eas`, the interactive chart engine, is its own package, eas.el (default
checkout `../eas.el`; `EAS=` overrides), which this package requires. Its
README and `docs/design/engine.md` live there. Here: the health templates,
the validator and the thin API over them (`docs/design/render-only.md`).

## Driving it

Ask the package; do not read source to learn its state.

1. Discover: `(health-chart-list-templates)` or `bin/health-chart templates`
   (name, group, one-line doc). `(health-chart-describe-template NAME)`
   gives slots, the rows each data slot takes and the rules between slots.
2. Learn the input: `(health-chart-example NAME)` or
   `bin/health-chart example NAME --raw > b.json` (bindings that render as
   is; the data is synthetic).
3. Check: `(health-chart-check NAME BINDINGS)` answers t or
   `(:code :path :index :field :message)`; `health-chart-validate` signals
   `health-chart-invalid-data` with the same data. Shell:
   `bin/health-chart validate NAME --data b.json` (exit 1 on failure).
4. Draw: `(health-chart-render NAME BINDINGS :backend 'text)` is
   deterministic; read it yourself. `:backend 'svg` for an image.
   `bin/health-chart render NAME --data b.json --backend text --raw`.
5. Show the human: `(health-chart-open NAME BINDINGS)`.
6. The other eas verbs (`check`, `explain --stage resolve|compile|scene`,
   `export --vl`, `doctor`) work through `bin/health-chart` with the health
   templates loaded.

## Changing it

- `make test EAS=...` (offline, no display) and `make compile EAS=...`
  (warnings are errors) and `make checkdoc` must pass. Goldens:
  `make goldens EAS=...`, then review the diff in `test/golden/`.
- Rendering is eas's. There is no renderer here: a new chart is
  `templates/NAME.json` (Vega-Lite plus an `x-eas` block of slots), its
  `examples/NAME.data.json` (synthetic bindings that render as is) and
  nothing else. Its `x-eas.health` block declares the group, the default
  sizes and what each data slot takes (field types and rules, documented in
  `src/health-chart-validate.el`); the test suite then breaks every declared
  field and expects the right code and path, and checks the example against
  text and SVG goldens. `make screenshots` regenerates `docs/screenshots/`.
- Errors: `define-error` under `health-chart-error`, data `(MESSAGE :code
  CODE :path PATH :index INDEX :field FIELD)`; the message says how to fix
  it. Never message-and-return-nil.
- Data sources stay out: no fetching, no device or EHR integration, no
  reference-range tables. The data source owns every clinical range, cut-off,
  goal and category band; a template never carries one as a slot default
  (`make test` scans for it). Callers supply them as data (`ref_low` /
  `ref_high` in rows, `low` / `high` slots, `bands` rows with a `status`),
  and a missing range draws grey "no range", never green. The optional
  adapter `health-chart-from-biomarker` (src/health-chart-biomarker.el) is
  pure: it maps a `biomarker/v1` envelope it is handed, it runs nothing.
- One color rule, in one place. Red is out of range, yellow is within the
  warning margin of a limit, green is in range, grey is no range; nothing
  else is ever red, yellow or green (lab recency, overdue, adherence,
  categories, decorations use neutral colors, markers and words). The rule
  is `health-chart-status` (src/health-chart-status.el), reached from
  templates through the `health-status` / `health-band-status` eas
  transforms; colors, the margin and the surface colors are
  `health-chart-theme` (src/health-chart-theme.el), which fills the slot
  defaults of every template, so a template's JSON declares those slots
  (`bad_color`, `warn_color`, `ok_color`, `unknown_color`, `line_color`,
  `warn_margin`, `ink`, `secondary`, `muted`, `surface`, `grid`) without a
  default. Legends say low / near limit / in range / high / no range.
- Example data is always synthetic and labelled so. Never commit real
  patient data.
- No personal paths, machine names or emails other than me@davidaw.ad in
  files or commit messages.
