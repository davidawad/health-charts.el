# Rendering through eas

Status: analysis (written before the code), then kept current as the
migration landed. Tracks `fc-qx1.20` (financial-chart store), which
also absorbs `fc-8yx`: the vitals and labs presets are health-charts'
kinds, so they are not built twice.

Reference pattern: financial-chart.el's `fc-uses-eas` branch
(`src/integrations/financial-chart-eas.el` registers adapters,
transforms and a template directory with eas's public registries;
`financial-chart-eas-route.el` maps kinds to templates and checks
parity). Engine design: eas.el `docs/design/engine.md`.

## What changes, in one paragraph

Today health-charts builds a neutral `chartspec/v1` plist in Lisp
(`health-chart-spec*`: rows with statuses, band extents, positions,
ticks, label placement, colors) and a backend fills a Vega-Lite or
gnuplot template from it with `{{placeholders}}`. After this change
the Vega-Lite templates are eas templates (`templates/eas/*.json`, chart/v1
with `x-eas` slots). The Lisp side is an adapter (`biomarker`) that
lowers measurements to tidy rows, plus domain transforms that do the
range and status logic inside the chart document (`status`,
`reference-band`, `change`, `staleness`, `trend`). The engine draws:
SVG in a GUI frame, text in a terminal, and `eas-show` gives hover,
crosshair, zoom, brush and linked views for free. The public API
(`health-chart-plot`, `-render`, `-write`, `-explain`, `-spec`, kinds,
props, Org blocks, CLI) is unchanged, and the gnuplot backend and
`chartspec/v1` stay as they are.

## What stays

- `health-chart-spec*` and `chartspec/v1`: the gnuplot backend, the
  native text/svg renderers and `health-chart-spec` (public) still use
  them. The transforms call the same Lisp rules (`health-chart-status`,
  `health-chart-ranges`, `health-chart-model--verdict`, the range-position
  helpers) rather than copying them, so there is one definition of
  "high", "optimal" and "improved".
- The model layer (`health-chart-model*`): selection (person, marker,
  since/until, from/to draws, latest per marker). Selection chooses
  which measurements enter the chart; it is not drawing, and it runs
  before the adapter.
- The gnuplot backend and `templates/gnuplot/`.
- The native `text` renderer: still the last-resort terminal fallback
  when eas is not installed, and the only renderer of `table`,
  `sparkline`, `scorecard`, `cohort` (not among the 13 kinds migrated).

## Backends after the change

| backend | role |
|---|---|
| `eas` (new, default when eas is on `load-path`) | svg and text, every migrated kind; interactive via `health-chart-show` |
| `vega-lite` | external vl2svg/vl2png/vl2pdf. Bundled kinds are served by exporting the resolved eas template (`eas-resolve`), so there is one template set; user templates in `vega-lite/` dirs still win |
| `gnuplot` | unchanged |
| `text`, `svg` (native) | unchanged; `svg` stays obsolete |

`health-chart-graphic-backends` becomes `(eas vega-lite gnuplot)` and
`health-chart-terminal-backends` `(eas gnuplot text)`. When eas is not
loadable the `eas` backend reports unavailable and selection falls
through to the old order, so health-charts still works without it.

## Kind to template mapping

Template names carry a `health-` prefix: eas's registry is one flat
namespace and eas already ships `heatmap`, `line`, `bars`, `area` and
others (see gaps).

| kind | eas template | rows (adapter) | domain transforms, in order | native pieces |
|---|---|---|---|---|
| timeseries | `health-timeseries` | one marker, one person, by date | `status`, `reference-band` (value, domain) | rect (bands, aggregate collapses them), line, point (color+shape by status), text (latest) |
| compare | `health-compare` | one marker, every person | `status`, `reference-band` | line + point by person, `window` rank for the latest label, text |
| panel | `health-panel` | one person, several markers | `status`, `reference-band` | `facet` by marker, independent y, as timeseries per cell |
| trend | `health-trend` | one marker | `status`, `reference-band`, `trend` | timeseries layers + rolling-mean line + fit rule |
| lollipop | `health-lollipop` | one marker | `status`, `reference-band`, `lollipop-base` via `reference-band` `base` | rule (stem), point, rule (limit) |
| bullet | `health-bullet` | latest draw per marker | `status`, `reference-band` (domain scale) | bar tracks, tick, point, text |
| heatmap | `health-heatmap` | every draw of one person | `status` | rect + text, ordinal date x |
| delta | `health-delta` | the two chosen draws per marker | `status`, `change` | bar (diverging), rule at 0, text |
| strip | `health-strip` | every draw of every marker with a scale | `status`, `reference-band` (range scale) | bars (bands), tick (earlier draws), point (latest) |
| dumbbell | `health-dumbbell` | first and latest draw per marker | `status`, `change`, `reference-band` (range scale, columns before/after) | rule, two points, text |
| dual | `health-dual` | two markers | `status` | two layers, `resolve` independent y, axes left and right |
| inrange | `health-inrange` | every draw of each marker | `status` | `aggregate`, `joinaggregate`, `stack` normalize, text |
| staleness | `health-staleness` | indicator values (adapter `indicator-values`) | `staleness` | bar, rules (due, stale), text |

## Adapters

- `biomarker`: canonical measurements (the existing `measurements`
  shape, after `health-chart-fill-ranges`) to rows
  `{person, marker, label, unit, date, value, ref_low, ref_high,
  opt_low, opt_high, flag, category}`; failures are `SHAPE_INVALID` with
  `index`, from `health-chart--validate-measurements`.
- `indicator-values`: canonical indicator values to rows
  `{id, label, value, unit, date, as_of, marker, person, cohort}`.

## Transforms

All are registered with `eas-register-transform` and a schema, and each
calls the package's own rules.

| transform | in | adds |
|---|---|---|
| `status` | rows with value and ranges | `status`, `glyph`, `status_label` ("glyph word"), `value_label`, `out` (0/1) |
| `reference-band` | rows with ranges; `scale` = `value` (default), `domain` or `range`; `domain`, `ref`, `optimal`, `of`, `base` | `value`: `y_lo`, `y_hi` (padded domain of the marker), `ref_y`, `ref_y2`, `opt_y`, `opt_y2`, `ref_label`, `opt_label` clamped to the domain. `domain`: per-marker 0..1 `pos`, `ref_x`, `ref_x2`, `opt_x`, `opt_x2`, `ref_range`, `opt_range` (bullet). `range`: `norm`, `x`, `clipped` and the same band columns (strip, dumbbell) |
| `change` | rows of two draws per marker | one row per marker: `before`, `after`, `change`, `pct`, `pct_label`, `verdict`, `glyph`, `verdict_label`, `value_label`, `side` |
| `staleness` | indicator rows | `days`, `state`, `glyph`, `state_label`, `days_label`, `bar`, stalest first |
| `trend` | one marker's rows | `roll` (centred 3-draw mean), `fit` (least squares), `trend_label` |

Domain transforms must precede native ones in an array and only act on
the node that owns the data (`eas-resolve--materialize`), so every
template puts them on the root and the layers use native `filter` and
`aggregate`.

## Slots every template shares

`data`, `title`, `subtitle`, `description`, `config` (a Vega-Lite
`config` object: font, axis colors, background from the theme),
`status_domain` / `status_range` / `status_shape` (parallel arrays, so
the legend reads glyph + word, never color alone), `band_domain` /
`band_range`. Placeholders cannot reach into an object slot (`x-eas:slot`
replaces a node with the whole value), so a palette is a handful of
arrays rather than the `{{colors.ink}}` paths the old templates used.

## Gaps in eas

Found while reading eas and prototyping; confirmed ones are marked and
updated at the end of this document. eas itself is not changed.

(filled in below as they are confirmed)

## Verification plan

`make test` and `make compile` with `EAS=/path/to/eas.el`, niced, one
process. Each kind rendered once in batch as text from
`examples/sample-panel.json` and read. No eas gallery runs. Synthetic
data only.
