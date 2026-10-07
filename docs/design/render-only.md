# Render-only health charts on eas

health-chart draws data its caller supplies. It does not fetch, store or
interpret it. The shape is the same as financial-charts.el's: declarative
JSON in, strict validation with reason codes and JSON paths, drawing by eas
templates, text and SVG out, goldens for both.

## Layers

```
bindings (JSON / plist)
   -> health-chart-validate   (src/health-chart-validate.el)  codes + paths
   -> eas template            (templates/NAME.json)           Vega-Lite + x-eas slots
   -> eas-resolve, eas-compile, eas-text-render | eas-svg-render
```

- `src/health-chart-eas.el` registers `templates/` under the namespace
  `health` and loads `src/health-chart-transforms.el` (the domain transform
  `time-of-day-percentiles`, for the AGP), `src/health-chart-theme.el` and
  `src/health-chart-status.el`.
- `src/health-chart-theme.el`: the one place for the status colors, the
  warning margin and the surface colors (`health-chart-theme`,
  `health-chart-template-theme`). It fills the slot defaults of every
  `health/` template when eas looks the template up, so the JSON declares
  the slots without defaults and one setting reaches every template.
- `src/health-chart-status.el`: the color rule as pure functions
  (`health-chart-status`, `health-chart-status-limits`,
  `health-chart-status-bands`, `health-chart-status-band`) and its two eas
  transforms, `health-status` (a range) and `health-band-status`
  (category bands). Templates call the transforms, so the rule is one
  tested function and not an expression copied into 20 templates.
- `src/health-chart-biomarker.el`: `health-chart-from-biomarker`, the pure
  input adapter for the `biomarker/v1` envelope.
- `src/health-chart-core.el`: typed errors and template lookup.
- `src/health-chart-validate.el`: a table-driven validator. Each template
  declares what it takes in `x-eas.health` (`tables`, `slots`, `rules`,
  `group`, default sizes), so adding a template adds no Lisp, and the test
  suite derives its error cases from the same declaration.
- `src/health-chart.el`: the API. `src/health-chart-cli.el`: `bin/health-chart`.

What was removed from the earlier eas port: the gnuplot and Vega-Lite
command-line backends, the native text and SVG renderers, chartspec, the
biomarker source and model layers (selection, ranges; the status rule came
back as the small pure function above), cohorts,
indicators, genetics, Org blocks, the batch CLI and the data adapters. A
chart that needs a range or a threshold takes it as a slot.

## Conventions every template follows

- Out-of-range, flagged or categorical states use colour and shape or a
  glyph or text, never colour alone.
- One color meaning: red is out of range, yellow is within the warning
  margin of a limit (default 0.2 of the range width, 0.2 of the bound for a
  one-sided range), green is in range, grey is no range. Nothing else is red,
  yellow or green; lab recency, overdue vaccines, missed doses and the like
  use neutral scales and words. Legends say low / near limit / in range /
  high / no range.
- Clinical ranges, cut-offs, goals and category bands are data, never slot
  defaults (HbA1c categories, BMI classes, CKD stages, glucose targets,
  vitals ranges, growth percentiles all arrive in the bindings). The
  examples carry illustrative values and say so.
- Examples are synthetic and say so in the title.

## Findings about eas (version 0.2.2)

Each has a workaround in the templates.

1. A layer that only has `datum` constants draws once per data row; reduce
   it first with `aggregate` (count). A datum band does not widen the scale
   domain, so bands are computed fields (`lo`, `hi`) with `y`/`y2` fields.
2. Expression strings take real characters, not `\u` escapes; the JSON file
   escapes them.
3. An optional number slot needs a default (null with `x-eas:when`), or it
   fails as `SLOT_MISSING` when unbound.
4. `concat` with `columns` plus `x-eas:each` replaces facets (templates
   cannot hold a facet). A layer can bind a second named dataset to a second
   table slot.
5. Text target: rects draw solid (no opacity), so bands get edge rules and
   status grids carry text; quantitative colour is invisible, so heat grids
   carry their numbers; label row counts must match band steps.
6. Text labels at the right edge of the plot are clipped in SVG;
   curve labels in the growth chart sit above the line end.
7. Percentiles other than the quartiles are not an eas aggregate; the AGP
   uses a registered transform.

## Dropped or limited

Nothing in the requested list was dropped. Limits: the text rendering of
`ecg-strip` is dense (every minor gridline is a full line); the percentile
curves of `growth-chart` are neutral greys in text; the package ships no
CDC or WHO curves (the caller binds them).
