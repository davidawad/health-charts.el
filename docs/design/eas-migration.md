# Rendering through eas

Status: landed on branch `on-eas` (analysis first, then the code). Tracks
`fc-qx1.20` in financial-chart's store, which also absorbs `fc-8yx`: the
vitals and labs presets are health-charts' kinds, so they are not built
twice.

Reference pattern: financial-chart.el's `fc-uses-eas` branch
(`src/integrations/financial-chart-eas.el` registers adapters,
transforms and a template directory through eas's public registries;
`financial-chart-eas-route.el` maps kinds to templates and checks
parity). Engine design: eas.el `docs/design/engine.md`.

## What changed, in one paragraph

Before, health-charts built a neutral `chartspec/v1` plist in Lisp
(`health-chart-spec*`: rows with statuses, band extents, positions,
ticks, label placement, colors) and a backend filled a Vega-Lite or
gnuplot template from it with `{{placeholders}}`. Now the Vega-Lite
templates are eas templates (`templates/eas/health-KIND.json`, chart/v1
with `x-eas` slots). Lisp supplies an adapter (`biomarker`) that lowers
measurements to tidy rows and domain transforms that do the range and
status logic inside the chart document. The engine draws: SVG in a GUI
frame, text in a terminal, and `health-chart-show` opens an `eas-show`
view with hover, crosshair, zoom and the agent verbs. The public API
(`health-chart-plot`, `-render`, `-write`, `-explain`, `-spec`, the kinds,
props, Org blocks, the CLI) is unchanged, and so is the gnuplot backend.

## What stays

- `health-chart-spec*` and `chartspec/v1`: the gnuplot backend, the
  native text/svg renderers and the public `health-chart-spec` still use
  them, and `health-chart-eas-parity` checks every eas template against
  them row by row. The transforms call the same Lisp rules
  (`health-chart-status`, `health-chart-ranges`,
  `health-chart-model--verdict`, the range-position helpers of
  `health-chart-spec-gallery.el`) instead of copying them: one
  definition of "high", "optimal" and "improved".
- The model layer (`health-chart-model*`): selection (person, marker,
  since/until, from/to draws, latest per marker). Selection chooses
  which measurements enter a chart; it is not drawing and runs before
  the adapter, inside each kind's bindings function.
- The gnuplot backend and `templates/gnuplot/`.
- The native `text` renderer: the last-resort terminal fallback without
  eas, and the only renderer of `table`, `sparkline`, `scorecard`,
  `cohort` (not among the thirteen migrated kinds).

## Backends

| backend | role |
|---|---|
| `eas` (new) | svg and text for every migrated kind; first in both `auto` lists when eas.el loads |
| `vega-lite` | external vl2svg/vl2png/vl2pdf. A bundled kind is drawn by exporting its resolved eas template (`eas-resolve`, with pixel sizes in place of `"container"`); a Vega-Lite template of the user's own in `health-chart-template-directories` still wins. The bundled `templates/vega-lite/` files are gone |
| `gnuplot` | unchanged |
| `text`, `svg` (native) | unchanged; `svg` stays obsolete |

`health-chart-graphic-backends` is `(eas vega-lite gnuplot)` and
`health-chart-terminal-backends` `(eas gnuplot text)`. eas is a soft
dependency: without it on `load-path` the `eas` backend reports itself
unavailable (`health-chart-eas-available-p`), `auto` falls through, and
explicit `:backend 'eas` signals `backend_missing` with the install hint.
Without eas the `vega-lite` backend draws only user templates, so images
come from gnuplot.

## Kind to template mapping

Template names carry a `health-` prefix: eas's template registry is one
flat namespace and eas already ships `heatmap`, `line`, `bars`, `area`
and others.

| kind | eas template | rows (adapter `biomarker`) | domain transforms, in order | native pieces |
|---|---|---|---|---|
| timeseries | `health-timeseries` | one marker, one person | `status`, `reference-band` | invisible frame rect, band rects (aggregate), line, point (color + shape by status), text (latest) |
| compare | `health-compare` | one marker, every person | `status`, `reference-band` | `window` row_number for the latest, line + point by person |
| panel | `health-panel` | one person, several markers | `status`, `reference-band` | hconcat of up to four vconcat columns, cells by `x-eas:each` |
| trend | `health-trend` | one marker | `status`, `reference-band`, `trend` | timeseries layers, rolling-mean line, dashed fit, slope text |
| lollipop | `health-lollipop` | one marker | `status`, `reference-band` (`base`) | rules (stems, limit), point, text (gap) |
| bullet | `health-bullet` | latest draw per marker | `status`, `reference-band` (`domain`) | bar tracks and bands, tick, point |
| heatmap | `health-heatmap` | every draw of one person | `status` | rect + text, ordinal date x |
| delta | `health-delta` | the two chosen draws per marker | `status`, `change` | diverging bar, rule at 0, text |
| strip | `health-strip` | every draw of every ranged marker | `status`, `reference-band` (`range`) | bands, ticks (earlier draws), point (latest) |
| dumbbell | `health-dumbbell` | first and latest draw per marker | `status`, `change`, `reference-band` (`range`, `of` before/after) | rule, two points |
| dual | `health-dual` | two markers, tagged left/right | `status`, `reference-band` (`limit`) | independent y scales, one layer set per side |
| inrange | `health-inrange` | every draw of each marker | `status` | `aggregate`, `joinaggregate`, `stack` normalize, text |
| staleness | `health-staleness` | indicator values (adapter `indicator-values`) | `staleness` | bar, rules (due, stale), text |

Each template's own numbers are checked against the kind's chartspec by
`health-chart-eas-parity` (marks `draws`, `cells`, `latest`, `change`,
`days`, ...; strip by range positions, inrange by status counts), and
each example in `examples/eas/` passes eas's `check` natively.

## Adapters and transforms

- `biomarker`: canonical measurements, or anything
  `health-chart-source-normalize-list` reads (JSON arrays, snake_case or
  kebab-case members, a biomarker/v1 envelope), to rows `{person, marker,
  label, unit, date, value, ref_low, ref_high, opt_low, opt_high, flag,
  category}`; a draw with no ranges takes its marker's; failures are
  `SHAPE_INVALID` with `index`. An `:axis` member rides along for `dual`.
- `indicator-values`: indicator values to `{id, label, value, unit, date,
  as_of, marker, person, cohort}`.

| transform | in | adds |
|---|---|---|
| `status` | rows with value and ranges | `status`, `glyph`, `status_label` ("glyph word"), `value_label`, `value_text`, `out` |
| `reference-band` | rows with ranges; `scale` `value` (default), `domain`, `range`; `ref`, `optimal`, `base`, `limit`, `of`, `domain` | `value`: `ref_y`, `ref_y2`, `opt_y`, `opt_y2` clamped to the marker's padded range `y_lo..y_hi`, the labels and a `band_note`, and the padded date range `x_lo..x_hi` of all rows. `domain` (one row per marker): `pos`, `ref_x..opt_x2` on a padded 0..1 scale. `range`: `norm`, `x`, `clipped` per `of` column, bands as 0..1 positions, `x_lo`, `x_hi` display domain; markers with no ranges are dropped |
| `change` | rows of draws | one row per marker with two or more draws: `before`, `after`, `change`, `pct`, `pct_label`, `verdict`, `verdict_label`, `change_label`, `lim` |
| `staleness` | indicator rows | `days`, `state`, `glyph`, `state_label`, `days_label`, `bar`, `scale`; stalest first |
| `trend` | one marker's rows | `roll`, `fit`, `slope_per_year`, `trend_label` |

Domain transforms must precede native transforms in an array and only
act on the node that owns the data (`eas-resolve--materialize`), so every
template puts them on the root and the layers use native `filter` and
`aggregate`.

## Slots every template shares

`data`, `title`, `subtitle`, `description`, `config` (a Vega-Lite
`config`: background, axis, legend, title colors from the theme), the
palette roles `ink`, `secondary`, `muted`, `surface`, `grid`,
`ref_color`, `opt_color`, and `status_domain` / `status_range` /
`status_shape` (parallel arrays of the statuses present, so the legend
reads glyph and word, never color alone), plus `x_format` and `x_ticks`
for time axes. `x-eas:slot` replaces a whole node, so a palette is a few
strings and arrays rather than the `{{colors.ink}}` paths the old
templates used.

## Gaps in eas

Found while building this; eas itself was not changed. Each has a
workaround in the templates.

1. **No cancelling an inherited encoding channel.** `"x": null` is
   rejected with `INVALID_INPUT` ("An encoding channel must be an
   object"; `"y": null` goes through the same check, not tried). The Vega-Lite idiom lets a band or rule layer
   span a plot whose other layers share an x or y. Workaround: no root
   `encoding.x`/`y`; every layer that needs the channel states it.
2. **One color-family legend.** A `fill` encoding (datum or field) in one
   layer and a `color` legend in another collapse to one legend: the
   chart has two `legend` entries in Vega-Lite and eas draws only the
   color one. The reference and optimal bands therefore carry constant
   colors and are named by a text note (`band_note`) instead of a legend
   entry.
3. **Text legends are always on the right**, whatever `legend.orient`
   (documented in `eas-legend-orient.el`). Text marks that run past the
   plot (end-of-bar readouts) land on the legend. Workaround: readouts
   move into the y axis labels (`row_label`).
4. **Templates cannot hold a facet.** `eas-template-register` validates a
   template before slots resolve, and facet lowering needs inline data,
   so a top-level `facet` over a `{"name": ...}` data slot fails with "A
   view needs a mark, or a layer, vconcat or hconcat". There is no
   `concat` with `columns` either (only `vconcat`/`hconcat`), and
   `x-eas:each` cannot nest. `health-panel` is an `hconcat` of four
   `vconcat` columns, each expanded from its own slot.
5. **A failing template stops the registry load.** One template that
   fails validation makes `eas-template-reload` signal, and templates
   after it (in every `eas-template-directories` entry) never register;
   `(require 'health-chart-eas)` then fails whole.
6. **Placeholders cannot be partial.** A slot replaces a whole node: it
   cannot reach a member of an object slot, nor appear inside a
   `filter`/`calculate` expression string. The dual chart's per-side
   filter uses an `axis` column set by Lisp; the panel's per-marker
   filter uses the predicate form (`{"field": ..., "equal": item}`).
7. **No null slot default** (from reading the source, not tried). JSON
   `null` parses to `:null`, which axis code (`:values`, `:tickCount`)
   would read as set, so optional properties need a real default.
   Time-axis ticks are a `tickCount` number plus a
   format (`eas-layout.el` reads `tickCount` as a count, not Vega's
   `{interval, step}`), chosen in the bindings.
8. **Text target quirks.** The y axis labels shift one row against their
   bands when the x axis is at the top (`orient: "top"`), so the heatmap
   keeps its axis at the bottom. Band heights that are not a multiple of
   a text row (14 px) make tick labels drop on alternate rows and cell
   text and labels land on different rows; the heatmap takes a
   `row_step` slot (14 for text, 28 for svg). Rects with opacity under 1
   draw solid in text, so the reference and optimal bands differ only by
   face color.
9. **`eas-json-encode` returns UTF-8 bytes**, not characters, for
   non-ASCII text; callers must `decode-coding-string` it
   (`health-chart-eas--json`). Separately, `bin/eas render SPEC.json` on a
   spec file with a non-ASCII title (U+00B7) printed replacement
   characters in this shell; not investigated, so templates are ASCII or
   `\u` escapes.
10. **The template namespace is flat and global**, so a domain package's
    names must be prefixed (`health-`); eas's own `heatmap` would
    otherwise be replaced by the last template loaded.

Not gaps: every mark the old templates used (`rect`, `rule`, `text`,
`point`, `tick`, `bar`, `line`) and the shape channel, `window`
(`row_number`, `last_value`), `joinaggregate`, `stack`, `aggregate`,
`resolve` independent scales, `x2`/`y2`, `{"value": 0}` and
`{"datum": 0}` are supported; opacity-0 items still extend a scale
domain, which is how the invisible `frame` layer pads the axes.

## Verification

`make test EAS=/path/to/eas.el` and `make
compile EAS=...`, niced, one process, no eas gallery. Each kind rendered
once in batch as text from `examples/sample-panel.json` and read.
Synthetic data only. The eas tests (`test/health-chart-eas-test.el`)
skip without eas.el.

## Left

- Screenshots of the eas backend in the README (text is shown; the SVGs
  render, rasterizing them for `docs/screenshots/eas/` is not done).
- `health-charts` (the dashboard) still opens its chart sections as
  images or text through `health-chart-plot`; a key that opens
  `health-chart-show` on the marker at point is not added.
- `table`, `sparkline`, `scorecard`, `cohort` stay native text; eas has
  `sparkline` and `bars` templates they could use.
- CI: `.github/workflows` does not check out eas.el, so CI skips the eas
  tests and does not compile the eas files.
- The financial-chart bead `fc-qx1.20` is still open there; this branch
  is the work it tracks.
