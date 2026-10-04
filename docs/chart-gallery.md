# Chart gallery: patterns taken from the Vega-Lite examples

The [Vega-Lite example gallery](https://vega.github.io/vega-lite/examples/)
has about two hundred charts. This is the survey of which ones read
personal lab data well, which were taken, and which were rejected. The
picks are kinds you can draw with `health-chart-render`; each has a
Vega-Lite and a gnuplot template (`templates/vega-lite/KIND.vl.json`,
`templates/gnuplot/KIND.gp`) and no native text or SVG renderer, so
`:backend text` / `:backend svg` decline them with an error naming the
template backends (`unsupported_kind`), and `auto` picks a template
backend. In a terminal, `:backend gnuplot :format text` draws a rough
dumb-terminal version.

Lisp only derives what a template cannot: a linear fit, a value's
position in its reference range, a count of draws per status. All
drawing is in the templates. Every status color carries a glyph and a
word in the legend or labels.

| kind | data type | answers | gallery pattern |
|---|---|---|---|
| `trend` | one marker over time (weight, BMI, LDL-C, any slow drift) | which way is it going, how fast? | [Layering Rolling Averages over Raw Values](https://vega.github.io/vega-lite/examples/layer_line_rolling_mean_point_raw.html) |
| `lollipop` | one marker with an upper limit (hs-CRP, ApoB, triglycerides, ALT) | how far past the limit was each draw? | [Ranged Dot Plot](https://vega.github.io/vega-lite/examples/layer_ranged_dot.html) (rule plus point) |
| `strip` | many markers, many draws (hormones, CBC, a full panel) | where has each marker been inside its own range? | [Strip Plot](https://vega.github.io/vega-lite/examples/tick_strip.html) |
| `dumbbell` | many markers, two draws (annual review, before and after an intervention) | did each marker move toward or away from its range? | [Ranged Dot Plot](https://vega.github.io/vega-lite/examples/layer_ranged_dot.html) and [Slope Graph](https://vega.github.io/vega-lite/examples/line_slope.html) |
| `dual` | two related markers (glucose and HbA1c, ALT and AST, TSH and free T4) | do they move together? | [Dual Axis](https://vega.github.io/vega-lite/examples/layer_dual_axis.html) |
| `inrange` | many markers, all draws (time in range, a cohort or one person) | which markers are chronically out of range? | [Normalized (Percentage) Stacked Bar Chart](https://vega.github.io/vega-lite/examples/stacked_bar_normalize.html) |

## Picks

### `trend`: rolling mean and linear trend

Points are the draws, colored and shaped by status; a solid line is the
centred 3-draw rolling mean; a dashed line is the least-squares fit,
whose slope is written in the subtitle (`↘ falling 23.28 mg/dL per year
(linear fit)`; `→ flat` within 2 % over the span). It is the timeseries
chart plus the two things a reader does by eye anyway, and it keeps the
reference and optimal bands. Needs three draws for a fit; with fewer it
says `trend needs three draws`. The fit and the mean are computed in
Lisp (`roll`, `fit` on each row) so both backends draw identical lines.
Why it came from the gallery's rolling-average example: layering a
smoothed line over raw points is exactly what makes a noisy lab series
readable. Rejected from the same family: loess (needs more points than a
person has draws, and the curve would invent structure).

### `lollipop`: distance past the limit

One stem per draw from the marker's target limit (the optimal limit,
else the reference limit; upper edge, else lower) to the value, a status
shape on the tip, and the signed distance as a label (`+3.2`, `−0.2`).
For markers where "lower is better until it is not a problem"
(hs-CRP, ApoB, LDL-C) the stem length is the thing to read, which a
plain line hides. The stems are the rule-plus-point composition of the
ranged dot plot with one end pinned to the limit.

### `strip`: every draw on its own range scale

One row per marker; the x axis is each marker's reference range
rescaled so that 0 is the reference low and 1 the reference high, so
ferritin, TSH and testosterone share an axis. Grey ticks are earlier
draws, the status shape is the latest, and the label beside the row
gives the value and the status word. The optimal range is shaded
inside. It extends `bullet` (latest only) with the history, which shows
whether an in-range marker is steady or about to leave. Range position
is the one new derived field: `norm` (see `docs/chartspec.md`).

### `dumbbell`: first draw to latest

Per marker, a hollow dot for the first draw in the window and a filled
dot for the latest, joined by a rule colored by verdict
(`✔ improved`, `✖ worsened`, `● on-target`, `→ steady`; the same
verdict as `delta`, toward or away from the optimal range). Where
`delta` shows percent change, which is meaningless across a lab's
different units and ranges, the dumbbell shows movement relative to the
range: a 40 % fall of LDL-C from far above the range to inside it reads
very differently from a 40 % fall of ALT inside it. `:since` / `:until`
choose the window.

### `dual`: two markers, two axes

Dual-axis charts mislead when the two scales are arbitrary, so this one
is restricted to a pair a clinician reads together, each axis titled and
colored as its line, the second line dashed (a non-color channel), and
each marker's upper reference limit dotted on its own axis with its name
(`Glucose ≤99`). The latest values and their status words are in the
subtitle; points keep the status shapes. Pass `:marker '("glucose"
"hba1c")` (the default when both exist).

### `inrange`: share of draws per status

A 100 % stacked bar per marker: draws below the range, then optimal,
normal, suboptimal, then above. Counts are printed inside segments, the
right edge says `5/8 in range`, and markers are sorted worst first, so
the top of the chart is the to-do list. It is the lab equivalent of
time-in-range for glucose monitoring.

## Considered and not taken

| gallery chart | verdict |
|---|---|
| [Bullet chart](https://vega.github.io/vega-lite/examples/facet_bullet.html) | already `bullet` |
| [Error band](https://vega.github.io/vega-lite/examples/layer_line_errorband_ci.html) / ribbon for the range | already `timeseries` and `panel` draw reference and optimal bands; a ribbon would add nothing |
| [Text heatmap](https://vega.github.io/vega-lite/examples/layer_text_heatmap.html) | already `heatmap` (status glyph and value per cell); no clearly better gallery pattern, left alone |
| [Box plot](https://vega.github.io/vega-lite/examples/boxplot_2D_vertical.html) / [density](https://vega.github.io/vega-lite/examples/area_density.html) of a marker | one person has 4 to 12 draws per marker; a box or density of that many points is noise, and `strip` shows the points themselves. A distribution against a population reference needs reference data the package does not have |
| [Horizon graph](https://vega.github.io/vega-lite/examples/area_horizon.html) | compact, but banded color depth is hard to read and not accessible without color |
| [Streamgraph](https://vega.github.io/vega-lite/examples/stacked_area_stream.html) | labs are not additive parts of a whole |
| [Candlestick](https://vega.github.io/vega-lite/examples/layer_candlestick.html) | open/close semantics do not exist; the rule-and-bar idea is used in `dumbbell` |
| radial / polar charts | angle is a poor channel for comparing values; rejected for clarity |
| [Connected scatterplot](https://vega.github.io/vega-lite/examples/connected_scatterplot.html) | two markers against each other with time as the path; cute, but `dual` answers the same question with time on an axis |
| [Diverging stacked bar](https://vega.github.io/vega-lite/examples/bar_diverging_stack_population_pyramid.html) | `inrange` already diverges around the in-range segment |
| interactive selections ([brush](https://vega.github.io/vega-lite/examples/interactive_brush.html), crossfilter) | the charts are SVG/PNG images rendered by `vl2svg`; hover tooltips (every kind has them in the `.vl.json` and SVG) are the interactivity that survives. A template written for a browser can add selections |

## Adding another

Drop `templates/vega-lite/NAME.vl.json` (and optionally
`templates/gnuplot/NAME.gp`) into a template directory; the kind exists
as soon as the file does and receives the generic spec body. To derive
new fields, register the kind with a `:spec` builder, as
`health-chart-spec-gallery.el` and `health-chart-spec-dual.el` do for these six.
