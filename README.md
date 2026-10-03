# health-charts.el

Biomarker charts in Emacs: lab results in, chart out — propertized
unicode text in a terminal, SVG in a GUI. The health counterpart of
[financial-charts.el](https://github.com/davidawad/financial-charts.el),
with the same architecture: a kind registry, a shape registry, a
validate / explain / describe surface for programs and agents, two
renderers per kind, a JSON command line, and ert tests.

Data comes from plain Lisp (plists or alists) or from
[biomarker-cli](#data-source-biomarker-cli) through a thin, swappable
source layer. Every example in this file uses synthetic data.

- [Install](#install)
- [Use](#use)
- [Chart kinds](#chart-kinds)
- [The dashboard](#the-dashboard)
- [Data: plain Lisp](#data-plain-lisp)
- [Data source: biomarker-cli](#data-source-biomarker-cli)
- [For programs and agents](#for-programs-and-agents)
- [Command line](#command-line)
- [Customization](#customization)
- [Layout](#layout)
- [Tests](#tests)

## Install

Requires Emacs 29.1 or later. No dependencies; SVG display needs an
Emacs built with librsvg (text works everywhere).

```elisp
(use-package health-chart
  :load-path "~/src/health-charts.el"
  :commands (health-charts health-chart-plot health-chart-plot-view)
  :custom
  (health-chart-source-executable "biomarker")
  (health-chart-default-person "alex"))
```

or `(add-to-list 'load-path "~/src/health-charts.el")` and
`(require 'health-chart)`.

## Use

`M-x health-charts` opens the dashboard. `M-x health-chart-demo` shows
every kind over built-in synthetic data, no CLI needed.

From Lisp, one function draws any kind:

```elisp
(health-chart-plot KIND DATA &rest PROPS)        ; -> string
(health-chart-plot-insert KIND DATA &rest PROPS) ; at point
(health-chart-plot-view KIND DATA &rest PROPS)   ; in its own buffer
```

```elisp
(health-chart-plot 'timeseries (health-chart-source-trend :marker "ldl_c")
                   :backend 'text :width 72)
```

```
LDL-C · alex · mg/dL   latest 88 mg/dL (2025-06-02) ◐ suboptimal
    │●······
    │       ······●···
120 ┤                 ······
    │                       ···●···                    ···●··
    │                              ·······       ······      ····
100 ┤░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░···●···░░░░░░░░░░░░░░░░····░░░
    │░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░··●
 80 ┤░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    │░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    │▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒
    └───────────────────────────────────────────────────────────────────
     2024-03-04                  2024-10-17                   2025-06-02
● value   ▒ optimal ≤70   ░ reference 0–100
```

Common props:

| prop | meaning |
|---|---|
| `:backend` | `text`, `svg` or `auto` (default `health-chart-backend`: SVG when the frame can show it) |
| `:width` `:height` | text columns overall / plot rows |
| `:pixel-width` `:pixel-height` | SVG size |
| `:person` `:marker` | which person and marker to draw (default: the first present) |
| `:ref` `:optimal` | shade the reference / optimal band (default `health-chart-show-ref-range` / `-optimal-range`) |
| `:title` | replaces the derived title |
| `:from` `:to` | `delta`: the two draw dates (default: the latest two) |
| `:columns` | `panel`: cells per row |

Every status is shown as a glyph *and* a word, never color alone:
`● optimal`, `○ normal` (in range, no optimal range known),
`◐ suboptimal` (in the reference range, outside optimal), `▲ high`,
`▼ low`, `? n/a`. The reference and optimal bounds decide the status;
the source's `flag` is used only when a measurement has no ranges.

## Chart kinds

`(health-chart-list-kinds)` lists them; each has a text and an SVG
renderer.

| kind | shows |
|---|---|
| `timeseries` | one marker over time, reference (░) and optimal (▒) ranges shaded, points by status |
| `panel` | small multiples: a compact time series per marker |
| `table` | sparkline table: marker, latest, date, trend, flag, reference |
| `bullet` | range bars: where each latest value sits in its ranges |
| `heatmap` | markers by draw dates, each cell the draw's status |
| `compare` | one marker over time for several people, one glyph/color each |
| `delta` | percent change per marker between two draws, judged against target |
| `sparkline` | one-row sparkline of plain numbers |
| `scorecard` | indicator values: indicator, value, unit, status, trend sparkline |
| `cohort` | cohort panel: a card per indicator with value, status, range track, trend |
| `staleness` | days since each indicator's draw, against due and stale lines |

The last three take indicator values, not measurements; see
[Indicators and cohorts](#indicators-and-cohorts).

`table`:

```
Biomarkers · alex
Marker            Latest  Date        Trend         Flag          Reference
LDL-C           88 mg/dL  2025-06-02  █▇▄▂▅▁        ◐ suboptimal  0–100 (opt ≤70)
HDL-C           61 mg/dL  2025-06-02  ▁▃▆▅▃█        ● optimal     ≥40 (opt ≥60)
Triglycerides  104 mg/dL  2025-06-02  █▅▃▃▅▁        ◐ suboptimal  0–150 (opt ≤100)
hs-CRP          3.4 mg/L  2025-06-02  ▄█▃▁▄▇        ▲ high        ≤3 (opt ≤1)
```

`bullet`:

```
Latest vs range · alex
LDL-C          ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░┃░░░───   88 mg/dL  ◐ suboptimal
HDL-C          ───░░░░░░░░░░░░░░░░░░░░░░░░░┃▒▒▒   61 mg/dL  ● optimal
Vitamin D      ───░░░░▒▒┃▒▒▒▒░░░░░░░░░░░░░░░───   48 ng/mL  ● optimal
hs-CRP         ▒▒▒░░░░░░░░░░░░░░░░░░░░░░───┃───   3.4 mg/L  ▲ high
┃ latest   ▒ optimal   ░ reference   ─ outside
```

`heatmap`:

```
Out of range · alex
               24 24 24 24 25 25
               03 06 09 12 03 06  out
LDL-C           ▲  ▲  ▲  ◐  ▲  ◐  4/6
HDL-C           ◐  ◐  ◐  ◐  ◐  ●  0/6
Vitamin D       ▼  ◐  ◐  ●  ◐  ●  1/6
● optimal  ○ normal  ◐ suboptimal  ▲ high  ▼ low  · no draw
```

`delta` — a verdict per marker: `improved` / `worsened` (closer to /
further from the optimal range, or the reference range when there is no
optimal one), `on-target` (inside it both times), `steady`:

```
Change 2025-03-03 → 2025-06-02 · alex
LDL-C          112 → 88 mg/dL         ███│            -21.4%  improved
Vitamin D      36 → 48 ng/mL             │█████       +33.3%  improved
TSH            2.4 → 2.1 mIU/L         ██│            -12.5%  on-target
hs-CRP         2.1 → 3.4 mg/L            │█████████   +61.9%  worsened
```

`compare` overlays people with distinct glyphs (and colors in SVG):

```elisp
(health-chart-plot 'compare (health-chart-source-trend :marker "vitamin_d" :person nil)
                   :backend 'text)
```

SVG output uses a palette with selected light and dark variants
(`health-chart-svg-theme`), reserved status colors that always travel
with a glyph and a label, and a hover `<title>` on every point, bar and
cell. Each document carries a `<title>`/`<desc>` naming the kind and
data extent, so a saved file explains itself.

## The dashboard

`M-x health-charts` (an alias of `health-chart-dashboard`; with a prefix
argument it asks for the person) shows one person's sparkline table, then
the kinds in `health-chart-dashboard-sections` (range bars and the
heatmap by default).

| key | action |
|---|---|
| `RET` | open the marker at point as a time series |
| `m` | compare the marker at point across every person |
| `s` | select person |
| `c` | filter by category (`health-chart-marker-categories`) |
| `C` | select an indicator cohort (or `none`); its scorecard is drawn below the table |
| `K` | open the selected cohort as a cohort panel |
| `v` | small-multiples panel of the visible markers |
| `d` | change between the two latest draws |
| `g` | refetch from the source and redraw |
| `t` | toggle text / SVG for the chart sections |
| `r` / `o` | toggle the reference / optimal band |
| `n` / `p` | next / previous marker row |
| `q` | quit |

Chart buffers opened from it (`health-chart-plot-mode`) have `g`
(redraw), `t`, `r` and `o` too. Source errors are shown in the buffer
with the fix, never swallowed.

## Indicators and cohorts

An **indicator** is a named recipe — "latest ApoB", "days since the last
draw", "markers out of range" — described by an external catalog and
evaluated here over measurements. A **cohort** is a named set of
indicators (`cardio`, `metabolic`, `inflammation`, `vitamins`,
`overview`), kept as data in `health-chart-indicator-cohorts`.

```elisp
(health-chart-list-cohorts)                  ; summary per cohort, pure
(health-chart-describe-cohort 'cardio)       ; does each member resolve? is it in the catalog?
(health-chart-cohort-values 'cardio :person "alex")    ; fetch + evaluate -> indicator values
(health-chart-cohort-plot 'cardio :person "alex" :kind 'scorecard :backend 'text)
(health-chart-cohort-view 'vitamins 'staleness)        ; M-x health-chart-cohort-view
```

```
Indicators · cardio
Indicator        Value  Unit      Status        Trend
ApoB                84  mg/dL     ◐ suboptimal  █▆▃▂▄▁       ↘ improved
Lp(a)              140  nmol/L    ▲ high        ▁█           ↗ worsened
HbA1c              5.4  %         ○ normal      █▅▁          ↘ improved
Vitamin D           26  ng/mL     ▼ low         █▄▁          ↘ worsened
Ferritin           n/a  ng/mL     ? n/a
```

```
Days since draw · cardio · as of 2025-08-01
Lp(a)            2024-02-12  ████████████████████  536 d  ▲ stale
Vitamin D        2024-11-18  ██████████───│──────  256 d  ◐ due
ApoB             2025-06-02  ██──┆────────│──────   60 d  ● fresh
Ferritin         no draw     ────┆────────│──────      –  ? undated
┆ due after 120 d   │ stale after 365 d   ● fresh  ◐ due  ▲ stale
```

**The catalog.** `health-chart-indicator-catalog-function` (nil by
default) is a function called as `(FN RECIPE-ID)` → that indicator's
record, or nil, and as `(FN nil)` → every record (when it returns nil,
listing probes each known id instead). A record is the resource-catalog
object

```json
{"ref": {"kind": "indicator", "id": "health.cardio.apob"},
 "name": "Apolipoprotein B", "revision": "1.0.0",
 "attributes": {"description": "...", "owner": "...", "tags": ["health", "cardio"],
                "parameters": {}, "recipe": {...},
                "value": {"type": "number", "unit": "mg/dL", "scale": "linear",
                          "bounds": {"min": null, "max": 90}},
                "semantics": {"measure": "latest", "subject": {"kind": "biomarker", "key": "apob"},
                              "time_basis": "draw", "direction": "lower_is_better"}}}
```

as an alist, hash table or plist; its member names live only in
`health-chart-indicator-record-paths`. Without a catalog everything
still works from the local evaluator table; with one, cohort members are
checked against it and their records supply direction, bounds and unit.
To work without an external catalog, serve records from Lisp:

```elisp
(setq health-chart-indicator-catalog-function #'health-chart-indicator-catalog-static
      health-chart-indicator-catalog-static-data my-records)
(health-chart-indicator-list)               ; records tagged "health" (health-chart-indicator-tag)
(health-chart-indicator-list :tag nil)      ; every record
(health-chart-indicator-describe "health.vitamin-d")
```

**Evaluation.** A catalog recipe is a DAG, not elisp, so
`health-chart-indicator-evaluators` maps each recipe id to a local
measure (`latest`, `series`, `status`, `range-position`, `trend-slope`,
`days-since-draw`, `out-of-range-count`; see
`health-chart-indicator-measures`) and a marker — or a list of candidate
markers, the first present winning. An id without an entry is reported
unresolvable, never dropped; supporting a recipe is one data entry.
`health-chart-indicator-evaluate` and `health-chart-cohort-evaluate` are
pure over measurements you already hold.

**Status.** A value with reference or optimal ranges is judged like a
measurement. Otherwise its `direction` and `bounds` decide:
`lower-better` is `▲ high` above the max and `● optimal` below the min,
`higher-better` the mirror image, `in-range`/`neutral` `▼ low`/`▲ high`
outside; inside is `○ normal`. The trend word compares the series' ends
the same way: `improved`, `worsened`, `on-target`, `steady`, or `rising`
/ `falling` when the direction is neutral. Freshness is `● fresh`, `◐
due` (past `health-chart-indicator-due-days`, 120) or `▲ stale` (past
`health-chart-indicator-stale-days`, 365), counted to `:as-of` (default
the values' own as-of date, else today).

**Indicator values** — the data of the three indicator kinds — are
plists or JSON objects:

```json
{"id": "health.cardio.apob", "label": "ApoB", "cohort": "cardio", "value": 84,
 "unit": "mg/dL", "date": "2025-06-02", "as_of": "2025-08-01",
 "series": [104, 99, 91, 86, 93, 84], "direction": "lower_is_better",
 "bounds": {"min": null, "max": 90}, "ref_low": 0, "ref_high": 90, "opt_high": 80}
```

**Plans.** Every effectful call has a pure twin that names the calls it
would make and makes none:

| call | pure twin |
|---|---|
| `health-chart-indicator-list` | `health-chart-indicator-list-explain` |
| `health-chart-indicator-describe` | `health-chart-indicator-describe-explain` |
| `health-chart-describe-cohort` | `health-chart-describe-cohort-explain` |
| `health-chart-cohort-values` | `health-chart-cohort-values-explain` (incl. the biomarker argv) |
| `health-chart-cohort-plot` | `health-chart-cohort-plot-explain` (plus `health-chart-explain`) |

Errors: `health-chart-unresolvable-cohort` (`unknown_cohort`,
`unresolvable_cohort`), `health-chart-unknown-indicator`
(`unknown_indicator`, `unknown_measure`, `missing_marker`) and
`health-chart-catalog-error` (`catalog_missing`, `catalog_failed`), all
under `health-chart-error`. The doctor adds `indicator-catalog`,
`indicator-evaluators` and one `cohort:NAME` row per cohort; it never
calls the catalog.

## Data: plain Lisp

Charts take measurements in any of these forms, mixed freely — no CLI
involved:

```elisp
;; canonical plists
(:person "alex" :marker "ldl_c" :value 112.0 :unit "mg/dL" :date "2025-03-01"
 :ref-low 0 :ref-high 100 :opt-low nil :opt-high 70 :flag high)

;; plists with the wire names
(:marker "ldl_c" :value 112.0 :date "2025-03-01" :ref_low 0 :ref_high 100)

;; alists, as `json-parse-string' returns them (symbol or string keys)
((marker . "glucose") (value . 104) (date . "2025-04-10") (ref_low . 70) (ref_high . 99))

;; or a whole biomarker/v1 envelope
((schema . "biomarker/v1") (measurements . (...)))
```

Required: `marker`, `date` (`YYYY-MM-DD`) and a numeric `value`; the rest
is optional. `health-chart-source-normalize-list` returns the canonical
plists, and the helpers in `health-chart-core.el` work on them:
`health-chart-filter` (`:person :marker :category :since :until`),
`health-chart-latest`, `health-chart-by-marker`, `health-chart-status`.

```elisp
(health-chart-plot-view
 'bullet
 '(((marker . "glucose") (value . 93) (unit . "mg/dL") (date . "2025-06-02")
    (ref_low . 70) (ref_high . 99) (opt_low . 72) (opt_high . 90))
   ((marker . "vitamin_d") (value . 48) (unit . "ng/mL") (date . "2025-06-02")
    (ref_low . 30) (ref_high . 100) (opt_low . 40) (opt_high . 60))))
```

## Data source: biomarker-cli

`health-chart-source.el` is the only file that knows the biomarker CLI
and its wire format. It calls `health-chart-source-function`, a function
of `(COMMAND &rest ARGS)` where COMMAND is `query`, `trend`, `latest` or
`flag` and ARGS a plist of `:person :marker :since :until`:

```elisp
(health-chart-source-query :person "alex")          ; every measurement
(health-chart-source-trend :marker "ldl_c")          ; one marker, oldest first
(health-chart-source-latest :person nil)             ; newest draw per marker, everyone
(health-chart-source-flag)                           ; out-of-range draws
```

A request without `:person` uses `health-chart-default-person`.

The default function, `health-chart-source-cli`, runs

```
biomarker [--db DB] COMMAND [--person P] [--marker M] [--since D] [--until D] --format json
```

with `health-chart-source-executable`, `health-chart-source-db` and
`health-chart-source-extra-args`. It expects a JSON array of
measurements, or an envelope `{"schema": "biomarker/v1", "measurements":
[...]}`, and a measurement shaped

```json
{"person":"alex","marker":"ldl_c","value":112.0,"unit":"mg/dL","date":"2025-03-01",
 "ref_low":0,"ref_high":100,"opt_low":null,"opt_high":70,"flag":"high"}
```

A different schema (`biomarker/v2`), an `"error"` member, invalid JSON,
a non-zero exit or a missing executable each signal
`health-chart-source-error` with a `:code` (`schema_mismatch`,
`source_reported_error`, `bad_json`, `source_failed`, `source_missing`)
and a message naming the fix.

**This wire format is an assumption** made while biomarker-cli is being
built. If it settles differently, adjust `health-chart-source-fields`
(member names), `health-chart-source-list-keys` (envelope members) and
`health-chart-source-cli-args` (flags) — nothing else changes.

To use another source, set the function:

```elisp
;; Lisp data, no process
(setq health-chart-source-function #'health-chart-source-static
      health-chart-source-static-data (my-lab-results))

;; anything else
(setq health-chart-source-function
      (lambda (command &rest args)
        (my-fetch-measurements command (plist-get args :person))))
```

## For programs and agents

Ask the package; don't read source to learn its state.

```elisp
(health-chart-describe)              ; kinds, shapes, statuses, indicators, cohorts, source, entry points
(health-chart-describe-kind 'bullet) ; doc, shape doc, example data, renderers
(health-chart-validate 'table DATA)  ; t, or a typed error with :index
(health-chart-explain 'timeseries DATA :marker "ldl_c" :backend 'text)
(health-chart-doctor-checks)         ; (:name :status pass|fail|skip :detail :remediation)
```

`health-chart-explain` returns the exact renderer and args
`health-chart-plot` will use, why that backend, and a data summary
(points, markers, persons, date span, out-of-range count); it never
renders and never signals for bad data. Errors are `define-error`s under
`health-chart-error` with data `(MESSAGE :code CODE ...)`:

```elisp
(health-chart-validate 'table '(((marker . "tsh") (date . "2025-01-01") (value . "2"))))
;; => (health-chart-invalid-data "element 0: needs a numeric \"value\", got \"2\""
;;                                :code "invalid_data" :index 0)
```

Prefer `:backend 'text` to read a chart yourself; the text renderers are
deterministic.

New kind: write a text and an SVG renderer `(FN DATA &rest PROPS)`, then

```elisp
(health-chart-register-kind 'my-kind :shape 'measurements
                            :text #'my-text :svg #'my-svg :doc "What it shows.")
```

`describe` and the doctor pick it up.

## Command line

`bin/health-chart` drives the package from a shell with JSON:

```sh
bin/health-chart kinds
bin/health-chart example bullet > spec.json      # a spec render accepts as-is
bin/health-chart render spec.json
bin/health-chart explain spec.json
bin/health-chart validate spec.json              # {"ok":true} or the error envelope
bin/health-chart describe
bin/health-chart doctor
bin/health-chart cohorts
bin/health-chart cohort cardio '{"person":"alex","kind":"staleness"}'
bin/health-chart cohort-explain cardio '{"person":"alex"}'   # the plan, no I/O

# biomarker output straight in:
biomarker trend --marker ldl_c --format json | bin/health-chart pipe timeseries
biomarker query --person alex --format json  | bin/health-chart pipe heatmap '{"width":60}'
```

A spec is `{"kind": "...", "data": [...], ...props}`, props being the
keyword arguments of `health-chart-plot` without the colon
(`"backend": "svg"`, `"ref": false`). `data` may be a biomarker/v1
envelope. Failures print `{"ok":false,"error":{"code":...,"message":...}}`
and exit 1. Set `EMACS` to choose the Emacs binary.

## Customization

`M-x customize-group RET health-charts`. Highlights:

| option | default |
|---|---|
| `health-chart-backend` | `auto` |
| `health-chart-width`, `health-chart-height` | 72, 10 |
| `health-chart-show-ref-range`, `health-chart-show-optimal-range` | `t`, `t` |
| `health-chart-marker-labels` | `ldl_c` → `LDL-C`, … |
| `health-chart-marker-categories` | lipids, metabolic, inflammation, … |
| `health-chart-status-glyphs`, `health-chart-glyph-*` | the unicode glyphs |
| `health-chart-svg-theme`, `health-chart-svg-colors` | `auto`, per-role overrides |
| `health-chart-source-executable`, `-db`, `-extra-args` | `"biomarker"`, nil, nil |
| `health-chart-default-person` | nil (everyone / the first person) |
| `health-chart-source-function` | `health-chart-source-cli` |
| `health-chart-dashboard-sections`, `-backend` | `(bullet heatmap)`, `text` |
| `health-chart-indicator-catalog-function` | nil (no catalog) |
| `health-chart-indicator-cohorts`, `-evaluators` | cardio, metabolic, …; the `health.*` recipe ids |
| `health-chart-indicator-tag` | `"health"` |
| `health-chart-indicator-due-days`, `-stale-days` | 120, 365 |
| `health-chart-dashboard-cohort`, `-cohort-sections` | nil, `(scorecard)` |

Faces: `health-chart-optimal`, `-normal`, `-suboptimal`,
`-out-of-range`, `-ref-band`, `-optimal-band`, `-improved`, `-worsened`,
`-dim`, `-accent`, `-header`.

## Layout

| file | role |
|---|---|
| `health-chart.el` | entry point: `describe`, doctor, entry points |
| `health-chart-core.el` | customize group, faces, glyphs, dates, numbers, status, collection helpers |
| `health-chart-source.el` | the biomarker wire format, normalization, CLI and static sources |
| `health-chart-indicator.el` | indicator catalog hook and record format, indicator values, status, evaluators |
| `health-chart-cohort.el` | named indicator cohorts: resolve, describe, evaluate, fetch, plot, explain twins |
| `health-chart-model.el` | per-kind models both renderers draw from |
| `health-chart-text.el` | unicode renderers |
| `health-chart-svg.el` | SVG renderers |
| `health-chart-plot.el` | kind and shape registries, validate, explain, plot, chart buffer, demo |
| `health-chart-dashboard.el` | `health-charts` |
| `health-chart-batch.el`, `bin/health-chart` | JSON command line |

## Tests

```sh
make test       # ert, batch Emacs, offline; no biomarker install needed
make compile    # byte-compile, warnings are errors
make checkdoc
make lint PACKAGE_LINT=/path/to/package-lint   # dir holding package-lint.el
make check      # compile + checkdoc + test
```

The CLI path runs `test/fixtures/fake-biomarker`, which answers from
the JSON fixtures. Golden files in `test/fixtures/golden` pin every
kind's text and SVG output; regenerate with
`HEALTH_CHART_UPDATE_GOLDEN=1 make test` and review the diff.

`make lint` accepts package-lint findings for exactly one name, on
purpose: `health-charts`, the user-facing name of the customize group
and of the dashboard command alias, is off-prefix for the `health-chart`
package (two findings, one per definition). Anything else fails. See
`test/run-package-lint.el`.

## License

MIT. See [LICENSE](LICENSE).
