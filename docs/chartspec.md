# chartspec/v1

A chart spec is everything a backend needs to draw one chart, already
decided by Lisp: which rows, which statuses, which bands, which ticks,
which words. A template only lays it out. The same spec feeds every
backend, so a Vega-Lite chart and a gnuplot chart of the same data can
never disagree about a value or a status.

```elisp
(health-chart-spec KIND DATA &rest PROPS)   ; -> plist, pure
(health-chart-spec-to-json SPEC &optional PRETTY)
(health-chart-spec-from-json JSON)
```

From the shell: `bin/health-chart spec spec.json`.

The plist and the JSON are the same tree: plist keys are the JSON
member names as keywords (`:ref_low`, `:status_label`), arrays are
vectors, null is nil. `(equal spec (health-chart-spec-from-json
(health-chart-spec-to-json spec)))` holds. Every member below is always
present (null or `""` or `[]` when it does not apply), so a template can
reference it without checking.

Status is never color alone: every row, legend entry and annotation
that carries a color also carries a glyph and a word.

## Top level

| member | type | meaning |
|---|---|---|
| `schema` | string | `"chartspec/v1"` |
| `kind` | string | the chart kind; names the template file |
| `title`, `subtitle` | string | derived (`"LDL-C · alex"`, `"latest 76 mg/dL on 2025-09-15 · ◐ suboptimal"`); `:title` / `:subtitle` props replace them |
| `unit` | string | the marker's unit, `""` when none |
| `width`, `height` | number | CSS pixels (`:pixel-width` / `:pixel-height`; multi-row kinds size `height` from their rows) |
| `text_width`, `text_height` | number | columns / rows for text output (`:width` / `:height`) |
| `theme` | string | `"light"` or `"dark"` (`:theme`, `health-chart-theme`) |
| `font`, `font_size` | string, number | `health-chart-font-family`, `health-chart-font-size` |
| `colors` | object | the theme's palette, see below |
| `style` | object | `ref_band_opacity`, `opt_band_opacity`, `point_size`, `line_width`, `grid_opacity` |
| `x`, `y` | axis | see below |
| `layout` | object or null | kind-specific layout (panel: `columns`, `rows`, `cell_width`, `cell_height`) |
| `rows` | array | the data, one object per mark; `{{data}}` in a template |
| `overlays` | object | bands, thresholds, annotations |
| `legend` | array | legend entries, see below |
| `series` | array | per-series identity (compare: one entry per person) |
| `panels` | array | per-cell metadata (panel: one entry per marker: `index`, `marker`, `label`, `title`, `unit`, `latest_label`, `status`, `color`, `y_min`, `y_max`, `column`, `row`, and the band members of `overlays`) |
| `meta` | object | provenance: `points`, `from`, `to`, `persons`, `markers` (or `as_of`) |

### colors

`surface ink secondary muted grid axis` (chrome), `ref_band opt_band`
(bands), `optimal normal suboptimal low high unknown` (measurement
statuses), `improved worsened steady on_target` (change verdicts),
`fresh due stale undated` (draw freshness), and `series` (an array: the
fixed categorical order for people). Override any role with
`health-chart-colors`.

### Axes

| member | meaning |
|---|---|
| `type` | `temporal`, `quantitative`, `nominal` or `ordinal` |
| `title` | axis title, `""` for none |
| `domain` | `[lo, hi]` (dates as `"YYYY-MM-DD"`), or the category order for nominal axes |
| `domain_ms`, `domain_sec` | temporal only: the domain as epoch milliseconds (Vega) and seconds (gnuplot) |
| `ticks` | temporal only: `[{date, label, ms, sec}]`, month-aligned, at most about one per 110 px |
| `tick_format`, `tick_step_months` | temporal only: `"%Y"` for yearly ticks, `"%b %Y"` below; the same strftime codes work in Vega and gnuplot |
| `labels` | ordinal only (heatmap): display labels for `domain` |

Temporal domains are padded by 4% of the span (at least 20 days) each
side. Quantitative domains stretch to show nearby band edges and never
dip below zero for non-negative data.

### Rows (measurement kinds)

Every row of timeseries, compare, panel, bullet and heatmap has:

| member | example |
|---|---|
| `person`, `marker`, `label` | `"alex"`, `"ldl-c"`, `"LDL-C"` |
| `date`, `value`, `unit` | `"2025-09-15"`, `76`, `"mg/dL"` |
| `value_label` | `"76 mg/dL"` |
| `status`, `glyph`, `status_label` | `"suboptimal"`, `"◐"`, `"◐ suboptimal"` |
| `color`, `rgb` | `"#e09a00"`, the same as an integer (gnuplot `rgb variable`) |
| `shape`, `pt` | point shape: a Vega shape name and a gnuplot point type |
| `ref_low`, `ref_high`, `opt_low`, `opt_high` | the measurement's own ranges (null when open) |

Kinds add their own members:

| kind | extra row members |
|---|---|
| timeseries | `series` (the person), `latest` (1 on the newest row, else 0) |
| compare | `series`, `latest`, `series_label` (`"● alex"`), `series_color` |
| panel | `series`, `latest`, `latest_label`, `panel` (cell title), `panel_index`, `y_min`, `y_max`, `ref_y`, `ref_y2`, `opt_y`, `opt_y2` (the cell's drawn band extents) |
| bullet | `index`, `domain_lo`, `domain_hi`, `pos` (value on a 0..1 track), `ref_x`, `ref_x2`, `opt_x`, `opt_x2` (bands on the track, null when absent), `ref_range`, `opt_range`, `latest_label` |
| heatmap | `x_index`, `y_index` (1-based cell position), `date_label` (`"Nov 2021"`), `cell_label` (glyph and value, `"▲ 162"`), `out` (out-of-range count of the row's marker) |

Delta and staleness rows are not measurements:

| kind | row members |
|---|---|
| delta | `index`, `marker`, `label`, `unit`, `before`, `after`, `change`, `pct`, `pct_label` (`"-8.6%"`), `value_label` (`"84 → 76 mg/dL"`), `verdict` (improved, worsened, steady, on-target, unknown), `glyph`, `verdict_label` (`"✔ improved"`), `side` (`pos`/`neg`), `text` (the bar-end label, shortened when it would not fit), `color`, `rgb` |
| staleness | `index`, `id`, `label`, `date`, `days` (null when undated), `bar` (days, 0 when undated), `days_label` (`"536 d"` or `"no draw"`), `state` (fresh, due, stale, undated), `glyph`, `state_label` (`"◐ due"`), `text` (bar-end label), `color`, `rgb`, `marker`, `person` |

The gallery kinds (docs/chart-gallery.md) add:

| kind | extra members |
|---|---|
| trend | measurement rows plus `roll` (centred mean of up to three draws) and `fit` (the least-squares line at the row's date, null under three draws); `layout.trend` = `{slope_per_year, label, draws}` with `label` like `"↘ falling 23.28 mg/dL per year"` |
| lollipop | measurement rows plus `base` (the target's upper limit, else lower; optimal before reference), `gap` (value minus base), `gap_label` (`"+3.2"`); `overlays.thresholds` holds the limit line |
| strip | measurement rows, every draw, plus `index` (marker row), `draws`, `norm` (range position: 0 = reference low, 1 = reference high), `x` (`norm` clamped to `x.domain`), `clipped` (1 when clamped), `latest`, `ref_x`/`ref_x2` (0 and 1, null when the reference band is hidden), `opt_x`/`opt_x2` (the optimal band in range positions, open sides closed at the domain), `ref_range`, `opt_range`, `latest_label` |
| dumbbell | one row per marker with two draws: the later draw's measurement members plus `index`, `before`, `after`, `date_before`, `date_after`, `norm_before`, `norm_after`, `x_before`, `x_after`, `verdict`, `verdict_glyph`, `verdict_label`, `verdict_color`, `verdict_rgb`, `values_label` (`"162 → 76 mg/dL"`), `span_label`, `text` (the end label), and the strip band members |
| dual | measurement rows of both markers plus `series`, `series_label`, `series_color`, `axis` (`"left"`/`"right"`), `latest`; `layout.left` and `layout.right` = `{name, axis, label, title, unit, color, rgb, domain, latest_label}`; `overlays.thresholds` carry `axis`; `series` lists the two |
| inrange | one row per marker and status that occurs: `index`, `marker`, `label`, `unit`, `status`, `glyph`, `status_label`, `color`, `rgb`, `count`, `draws`, `x`/`x2` (segment start and end as a share of the marker's draws), `mid`, `seg_label` (the count, empty when the segment is narrow), `summary` (`"5/8 in range"`), `detail` |

Range position is the value on the marker's reference range, so markers
with different units share one axis. An open reference side is closed at
0 (low) or mirrored from the optimal edge (high); a marker with no range
at all is left out of `strip` and `dumbbell`.

Template-only kinds (a template with no registry entry) get every
measurement as a row, sorted by date, plus the timeseries members of
the first marker.

### overlays

| member | meaning |
|---|---|
| `ref_low`, `ref_high`, `opt_low`, `opt_high` | the raw bounds of the charted marker (null when open or hidden with `:ref nil` / `:optimal nil`) |
| `ref_y`, `ref_y2`, `opt_y`, `opt_y2` | the bands as drawn: open sides closed at the y domain, clamped to it; null when the band is hidden or outside the domain |
| `ref_label`, `opt_label` | `"reference 0–100"`, `"optimal ≤70"`, `""` when absent |
| `bands` | `[{key, label, low, high, y, y2, color, opacity}]`, the same bands as an array (handy for a Vega `rect` layer) |
| `thresholds` | `[{value, label, axis, key?, color?}]`: delta's zero line, staleness's due and stale lines |
| `annotations` | `[{date, value, text, status_label, color}]`: the latest value (`"latest 76 mg/dL"`); compare's read `"alex 55 ng/mL"` and add `series`, `series_label`, `series_color` and `label_y` (a y placed so labels never collide) |

### legend

`[{key, glyph, word, label, color, rgb}]`, best status first, only
entries that occur. Status entries add `shape` and `pt`. `label` is
glyph and word (`"▲ high"`, `"✔ improved"`, `"◐ due"`, compare: `"● alex"`).
A Vega color scale takes `{{legend.label}}` as its domain and
`{{legend.color}}` as its range; a gnuplot template loops over
`array LL = {{legend.label}}`.

## Placeholders

Templates reference spec members with `{{path}}`; see the README's
template authoring guide for the syntax and escaping rules.
