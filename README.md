# health-charts.el

Medical and health charts in Emacs from data you supply. health-chart
never fetches anything and never ships reference data or clinical ranges: you hand it plain
Lisp data (or JSON), it validates that data strictly, with a reason code
and a JSON path for every failure, and draws it through the
[eas.el](https://github.com/davidawad/eas.el) chart engine. One call
draws any of the 28 templates (vitals, labs, glucose, medication, sleep,
growth, ...) as text in a terminal frame or as an SVG image in a GUI
frame. Pure Elisp; the only external process is the optional PNG export
of the screenshots.

![Vitals dashboard rendered by health-charts.el](docs/screenshots/vitals-dashboard.png)

All example data in this repository is synthetic. Reference ranges in the
examples are illustrative and labelled so; the library ships none (see
[Colors and ranges](#colors-and-ranges)). **These charts are for
visualisation, not diagnosis or medical advice.**

Requires Emacs 30.1+ and [eas.el](https://github.com/davidawad/eas.el) 0.2.2+.

## Install

Install eas, then this package. On macOS or Linux with Homebrew the eas
command-line tool comes from the tap:

```sh
brew install davidawad/tap/easel
```

For Emacs (30.1 or newer), with `:vc`:

```elisp
(use-package eas
  :vc (:url "https://github.com/davidawad/eas.el" :lisp-dir "src"))
(use-package health-chart
  :vc (:url "https://github.com/davidawad/health-charts.el" :lisp-dir "src"))
```

or add both `src/` directories to `load-path` and `(require 'health-chart)`.

## Use

A chart is a template plus bindings: the data and the few numbers the
template needs (a reference range, a target). Bindings are JSON, or the
same thing as a Lisp plist.

```elisp
(require 'health-chart)

;; the synthetic example bindings of a template, drawn: SVG in a GUI
;; frame, text in a terminal
(health-chart-render "vitals-trend" (health-chart-example "vitals-trend"))

;; your own data
(health-chart-render
 "vitals-trend"
 '(:title "Resting heart rate" :y_title "Heart rate (bpm)" :low 60 :high 100
   :data [(:time "2026-03-01T08:00" :value 72)
          (:time "2026-03-02T08:00" :value 104)
          (:time "2026-03-03T08:00" :value 58)])
 :backend 'text)

;; from JSON, into a live view with hover, crosshair and zoom
(health-chart-open "bp-trend" (health-chart-read-bindings "bp.json"))

;; every template over its example
(health-chart-demo "agp")
```

From the shell, `bin/health-chart` is eas's command line with the health
templates registered (set `EAS` to your eas.el checkout if it is not
beside this repository):

```sh
bin/health-chart templates                                  # the catalog
bin/health-chart example vitals-trend --raw > b.json        # bindings that render as is
bin/health-chart validate vitals-trend --data b.json        # error code and JSON path, exit 1 on failure
bin/health-chart render vitals-trend --data b.json --backend text --raw
bin/health-chart render vitals-trend --data b.json --backend svg --raw > chart.svg
```

`check`, `explain`, `export --vl`, `describe` and `doctor` are eas's own
verbs (see its README); every verb answers the `chart/v1` envelope.

## The data contract

Every template takes **bindings**: an object keyed by the template's slots.
One or more slots are tables, lists of row objects (`data`, and for some
templates `curves`, `panels`, `bands`, `doses`, ...). The rest are scalars
(a title, `low` and `high` for a range, an `as_of` date). `describe`
shows both:

```elisp
(health-chart-describe-template "lab-trend")
;; => (:name "lab-trend" :doc ... :slots ... :tables (:data (:fields (:time "time" :value "number" ...))) ...)
```

Times are ISO 8601 strings (`2026-03-01`, `2026-03-01T08:30`, with an
optional seconds and zone), oldest first. Nothing is read from the
clock: a chart that needs "today" takes an `as_of` slot.

### Validation

Nothing is drawn until the bindings pass. `health-chart-validate` returns
`t` or signals `health-chart-invalid-data` (parent `health-chart-error`);
`health-chart-check` returns `t` or the same facts as a plist. The data
of the error is `(MESSAGE :code CODE :path PATH :index INDEX :field FIELD)`,
and `health-chart-error-data` returns it as a plist. `PATH` is a JSON path
such as `data[3].value`, `INDEX` the offending row and `FIELD` the offending
field. The message says how to fix it.

| Code | Meaning |
|---|---|
| `unknown_template` | no such template; the message lists them |
| `not_an_object`, `slot_unknown`, `missing_slot`, `slot_type` | the bindings as a whole: not an object, a slot the template lacks, a required slot left out, a slot of the wrong type |
| `not_a_list`, `too_few_rows`, `not_a_row` | a table is not a list, is empty, or holds a non-object |
| `missing_field` | a row lacks a required field (`data[0].value`) |
| `not_a_number`, `negative_value`, `not_an_integer`, `out_of_range` | numeric fields: not finite, below zero, not whole, outside 0..100, 0..1 or a declared range |
| `not_a_string`, `not_a_bool`, `not_in_enum` | text, boolean and choice fields |
| `not_a_time`, `not_a_date` | not an ISO 8601 date-time or date (checks the calendar: `2026-02-30` fails) |
| `time_not_ascending` | rows go back in time |
| `range_inverted`, `interval_inverted`, `diastolic_above_systolic`, ... | a low above its high, an end before its start |

## Colors and ranges

One color means one thing in every template.

| Color | Means | Shown also by |
|---|---|---|
| red | out of range: below the low limit or above the high limit | triangle down / `L`, triangle up / `H` |
| yellow | in range, but within the warning margin of a limit (a value exactly at a limit is yellow); or, where a row has an optimal range, inside the reference range but outside the optimal one ("suboptimal") | diamond, cross |
| green | in range, clear of both margins | circle |
| grey | no range to judge by (or no number) | square, "no range" |

Nothing else is red, yellow or green. Staleness (`lab-recency`), overdue
vaccines, late or missed doses, symptom severity, sleep stages, cycle phases
and the like use blues, greys and violets with markers and words, because
they are not out-of-range values. Every legend says low / near limit / in
range / high / no range (or the template's equivalent); a template that takes
an optimal range (`lab-results`, `lab-status-grid`, `lab-change`, `lab-trend`,
`lipid-panel`) adds suboptimal.

**Reference range against optimal range.** Red means unhealthy: outside the
reference range (`ref_low` / `ref_high`), nothing else. A row may also carry an
optimal range inside it (`opt_low` / `opt_high`): inside the reference range
but outside the optimal one is yellow and says "suboptimal"; inside the optimal
range is green. HDL 52 mg/dL (reference at least 39, optimal above 60) is
suboptimal, not low; total cholesterol 184 (reference 100 to 199, optimal below
180) is suboptimal, not high. The optimal limit replaces the warning margin on
its side; with only a reference range the margin applies as below. A value
exactly at a limit is inside it (at a reference limit: not red, at an optimal
limit: optimal). An optimal limit outside the reference range on its side is
ignored; an optimal range with no reference range at all is never red, outside
it is suboptimal. In `lipid-panel` the goal is the optimal limit and a
`ref_limit` per row is the reference limit on its side (without it the goal is
the limit, as before). `health-chart-from-biomarker` fills all of these from
`ref_low`, `ref_high`, `opt_low` and `opt_high` of the rows.

**The warning margin** is 20 percent of the range width, measured inward from
each limit. A range with one limit (only `ref_high`, or only `ref_low`) has no
width, so the margin is 20 percent of that limit. A value exactly at a limit
is in range and yellow; exactly at the inner edge of the margin it is green.
Two places on a template change it: a `warn_margin` binding (a fraction), and
per row `warn_margin`, or `warn_low` / `warn_high` (the value where yellow
turns green on that side). Where 20 percent of a range is the wrong idea the
template takes categories instead: `a1c-trend`, `egfr-trend` and
`weight-bmi-trend` get a `bands` table whose rows carry their own `status`
(`low`, `near`, `suboptimal`, `ok`, `high`), so what counts as borderline is the data
source's call, not a percentage.

**The ranges are data.** No template carries a clinical range, cut-off, goal,
category band or percentile curve as a default. They arrive as `ref_low` /
`ref_high` in rows, `low` / `high` slots, `goal` per measure, or a `bands`
table. A limit that is missing is drawn as missing: a result with no range is
grey, never green. The examples carry illustrative values and say so.

**Configure it once.** Colors, the margin and the surface colors live in one
place and every template reads them:

```elisp
(setq health-chart-theme
      '(:bad "#c0392b" :warn "#f0b400" :ok "#1e8e3e" :unknown "#8a8a8a"
        :warn-margin 0.1))                       ; also :line :ink :secondary :muted :surface :grid
(setq health-chart-template-theme                 ; per-template overrides
      '(("vitals-trend" :warn-margin 0.05)))
```

A binding always wins over both (`bad_color`, `warn_color`, `ok_color`,
`unknown_color`, `line_color`, `warn_margin`, `ink`, `surface` ... as slots of
the template). The theme is presentation only: it holds no clinical value.
The rule itself is a pure function, `(health-chart-status VALUE LOW HIGH
&optional MARGIN WARN-LOW WARN-HIGH OPT-LOW OPT-HIGH)`, that answers `low`,
`near`, `suboptimal`, `ok`, `high` or `unknown`.

**Numbers are shown short, judged exact.** A computed float is drawn with 3
significant figures (82.916685236 is `82.9`, 4.551020408 is `4.55`), but never
with fewer decimals than the row's reference limits show (limits `0.0` and
`0.2` keep `0.02` as `0.02`) and never with a digit of the whole part cut (132
stays `132`). Labels, tooltips, grid cells and change arrows all use it. Three
levers: the `sig_figs` slot (theme key `:sig-figs`), the `decimals` slot for an
exact count, and a per-row `decimals` field that wins over both. The status
rule always sees the number as it came: `5.6004` against a limit of `5.6` is
drawn `5.6` and is still `high`. Row labels longer than the `label_max` slot
(theme `:label-max`, default 28 characters) end in an ellipsis, and
`lab-status-grid` cuts a value wider than its `col_step` cell the same way, so
a label and a value never run together. A grid also shows only as many draws
as its width holds: a column never gets narrower than its widest cell text plus
a space (in text cells, or in pixels for SVG), and when there are more draws
than that the latest ones are shown and the subtitle says so ("latest 6 of 12
draws"). A live view (`health-chart-open`) is fitted again whenever its window
is resized. The `max_draws` slot (`:max-draws` for
`health-chart-from-biomarker`) sets the number yourself; 0 shows every draw.
The columns are the draw dates of the markers shown: a marker drawn far more
often than the rest (more than 4 times the median number of draw dates, such
as daily weight beside a few lab draws) is left out by default, so its dates do
not crowd out the lab columns, and the subtitle names it; the
`include_frequent` slot (`:include-frequent`) keeps it. `health-chart-from-biomarker` takes
`:decimals`, `:sig-figs` and `:label-max` and sets those slots; the numbers it
maps are untouched.

**From the biomarker CLI.** `health-chart-from-biomarker` maps the
`biomarker/v1` envelope that `biomarker latest|query --format json` prints
into the bindings of `lab-results`, `lab-status-grid`, `lab-change`,
`lab-trend`, `lab-panel`, `lipid-panel`, `a1c-trend` and `weight-bmi-trend`.
It is pure (it reads only the envelope it is given, runs no process, opens no
file), and the ranges are the rows' own `ref_low`, `ref_high`, `opt_low` and
`opt_high`:

```elisp
(let ((env (health-chart-read-bindings "latest.json")))  ; biomarker latest --format json > latest.json
  (health-chart-render "lab-results" (health-chart-from-biomarker "lab-results" env)))
(health-chart-render "lab-trend"
                     (health-chart-from-biomarker "lab-trend" env :marker "hba1c"))
```

Options: `:title`, `:markers`, `:category`, `:marker`, `:height-m`, `:bands`,
`:margin`, `:directions`, `:all-markers`, `:include-frequent`. For
`lab-status-grid` only markers with a reference range in some row are drawn
unless `:markers` names them or `:all-markers` is set (when no marker has a
range, all are drawn). Rows without a numeric canonical value (a qualified
result such as "<5") are skipped.

## Template catalog

| Template | Group | What it draws |
|---|---|---|
| [`bp-trend`](#bp-trend) | Vitals | Blood pressure over time: each reading is a bar from diastolic to systolic, drawn over the systolic and diastolic ranges (green, yellow near each limit). Systolic and diastolic are judged separately; the reading is colored by the worse of the two: red out of range (triangle-down L low, triangle-up H high), yellow near a limit, green in range, grey when neither has a range. The ranges come from the data source via the sys_low/sys_high/dia_low/dia_high slots. |
| [`vitals-dashboard`](#vitals-dashboard) | Vitals | Five vitals on one time axis, each against its own range: heart rate, blood pressure (systolic and diastolic), temperature, SpO2 and respiratory rate. Each range is a band (green, yellow near each limit); readings are red out of range (triangle-down low, triangle-up high), yellow near a limit, green in range, grey when that metric has no range. The ranges come from the data source via the hr_/sbp_/dbp_/temp_/spo2_/rr_ low and high slots; a missing pair is grey no range. |
| [`vitals-trend`](#vitals-trend) | Vitals | One vital sign over time against its normal range: the range as a band (green, yellow near each limit) and each reading colored red out of range, yellow near a limit, green in range, grey with no range, flagged L or H by shape and letter. The range comes from the data source via the low/high slots. |
| [`ecg-strip`](#ecg-strip) | Heart and rhythm | An ECG-style strip: millivolts against seconds over ECG paper (small boxes 0.04 s by 0.1 mV, large boxes 0.2 s by 0.5 mV). A drawing aid, not a diagnostic tool. |
| [`hrv-trend`](#hrv-trend) | Heart and rhythm | Daily heart-rate variability (RMSSD) with a 7-day rolling mean and a personal baseline band (green, yellow near each edge); days below the baseline are red and flagged L, days above it red and flagged H. The baseline comes from the data via the low/high slots. Legend words: below baseline / near edge / within baseline / above baseline / no baseline. |
| [`lab-change`](#lab-change) | Lab results | Before and after for each analyte on its own reference range: a dumbbell from the earlier result (hollow) to the later one (filled) over the range bar (green, yellow near each limit). Each marker is colored by its own status (red out of range, yellow near a limit, green in range, grey with no range) and shaped by direction. The connecting line and the word at the right say how the result moved, in neutral colors: improved (nearer the range, or inside it nearer its middle), worsened, unchanged, or no range when no direction can be decided; this is not a health status. |
| [`lab-panel`](#lab-panel) | Lab results | Small multiples: one compact trend per analyte, each on its own scale with its own reference range (from the panels table) as a band, green with yellow zones near each limit; every result is colored red out of range, yellow near a limit, green in range or grey with no range, and shaped by direction. The range is data, never a template default. |
| [`lab-recency`](#lab-recency) | Lab results | How long ago each test was last drawn, against how often it is due: a bar of days since the last draw and a tick at the interval. Staleness is not a health status, so it is drawn in blues only: lighter within the interval, deeper when overdue (up to overdue_factor times the interval), darkest when long overdue, grey when never drawn; each state is also written next to its bar. The reference date as_of is supplied, never read from a clock. |
| [`lab-results`](#lab-results) | Lab results | Latest result of many analytes, each placed within its own reference range: the range is the bar (green, yellow near each limit or outside the optimal range), the result a marker colored red out of range, yellow near a limit or outside the optimal range (suboptimal), green in range and grey when there is no range. |
| [`lab-status-grid`](#lab-status-grid) | Lab results | A grid of analytes by draw date: each cell is filled with its status color at partial opacity (red out of range, yellow near a limit or, with an optimal range, outside it (suboptimal), green in range, grey with no range) and carries a glyph (low, near, suboptimal, in range, high, ?) and the value, judged against that row's own reference range. Ranges come from the data, either limit may be missing. |
| [`lab-trend`](#lab-trend) | Lab results | One lab analyte over time against its reference range: the range as a band (green, yellow near each limit), an optional optimal band inside it, and each result colored red out of the reference range, yellow near a limit or outside the optimal range (suboptimal), green in range, grey with no range, and flagged L or H by shape and letter. |
| [`lipid-panel`](#lipid-panel) | Lab results | A lipid panel against goal lines: one bar per measure, a tick at its goal, an optional hollow marker for the prior draw. Each measure is judged against its own goal, a one-sided range: a 'below' goal has only an upper limit, an 'above' goal only a lower one. The bar is red only outside the reference limit (low means below an 'above' goal's reference limit, high above a 'below' goal's), yellow when the goal is missed but the reference limit is kept (suboptimal), green when the goal is met; a measure with no reference limit treats the goal as its limit: red when missed, yellow near it, green clear of it. The status is also written at the bar end. Goals and reference limits are data. |
| [`agp`](#agp) | Glucose and diabetes | Ambulatory glucose profile: many days of readings folded onto one 24 hour day as the median line with the 25-75th and 5-95th percentile bands (neutral blues) and, when the data source supplies it, the target range as a green band. The profile itself is not judged, so it uses no red or yellow. |
| [`cgm-day`](#cgm-day) | Glucose and diabetes | A continuous glucose monitor day: the glucose line over 24 hours against the target range from the data source (band: green, yellow near each limit); readings are red out of range (triangle-down low, triangle-up high, letter L or H), yellow near a limit, green in range, grey with no range. Optional very low / very high limits are drawn as labelled dashed rules; a reading beyond one is red like any out-of-range reading but larger and flagged with its letter and !! (dense days are not lettered otherwise). |
| [`time-in-range`](#time-in-range) | Glucose and diabetes | Time in range: the share of glucose readings very low, low, in range, high and very high per period (weeks, days, any label you give), computed from the raw readings against the four cut-offs from the data source (all required). Out-of-range shares are red (very low and very high solid, low and high tinted), in range is green. Shares have no warning margin, so there is no yellow. An optional target_pct draws a target tick on the in-range share. |
| [`a1c-trend`](#a1c-trend) | Trends against published categories (A1c, eGFR, BMI) | HbA1c (%) over time against category bands bound from the data source (each band carries its own status: low, near, ok or high); bands are filled and readings colored and shaped by that status, with an optional personal target line. |
| [`egfr-trend`](#egfr-trend) | Trends against published categories (A1c, eGFR, BMI) | Estimated GFR (mL/min/1.73 m2) over time against category bands bound from the data source (each band carries its own status: low, near, ok or high); bands are filled and readings colored and shaped by that status, with an optional personal target line. |
| [`weight-bmi-trend`](#weight-bmi-trend) | Trends against published categories (A1c, eGFR, BMI) | BMI over time, computed from weight and height, against category bands bound from the data source (each band carries its own status: low, near, ok or high); bands are filled and readings colored and shaped by that status; the weight is in the tooltip. |
| [`fluid-balance`](#fluid-balance) | Fluids | Fluid balance per day: intake bars up, output bars down, in millilitres, with the net balance marked and labelled; the totals are computed from the individual entries. |
| [`medication-timeline`](#medication-timeline) | Medication | Medication courses as neutral bars on a timeline, each scheduled dose marked taken (blue circle), late (light blue diamond) or missed (grey cross), with the adherence share per medication. |
| [`immunization-timeline`](#immunization-timeline) | Immunizations | Immunization history: one row per vaccine, doses given as blue circles, doses still due as grey diamonds and doses due before the as_of date as dark triangles labelled overdue (overdue is a scheduling state, not a health judgment). |
| [`symptom-diary`](#symptom-diary) | Symptoms | Symptom or pain diary: one row per symptom, one column per day, each cell shaded and numbered by the severity logged (0 none to 10 worst); a note rides in the tooltip. |
| [`cycle-tracker`](#cycle-tracker) | Cycle tracking | Menstrual cycle tracker: one row per cycle on a cycle-day axis, phases as labelled coloured segments and optional daily markers. The caller supplies every phase boundary; nothing is predicted. |
| [`growth-chart`](#growth-chart) | Growth | Paediatric growth chart: percentile curves bound by the caller (bind published CDC or WHO curves; this package ships none) with the patient's measurements drawn over them. The example curves are synthetic. |
| [`sleep-duration`](#sleep-duration) | Sleep | Nightly sleep as stacked bars by stage, the time in bed in hours above each night and, when a goal is supplied, the sleep goal as a dashed line. |
| [`sleep-hypnogram`](#sleep-hypnogram) | Sleep | One night of sleep as a hypnogram: the stage (awake, REM, light, deep) over time, one segment per stage change. |
| [`activity-calendar`](#activity-calendar) | Activity and fitness | A calendar heatmap of a daily count such as steps: weeks as columns, weekdays as rows, color by value, a check mark on days that met the goal. |
| [`hr-zones`](#hr-zones) | Activity and fitness | Time spent in each heart-rate zone as horizontal bars, with the zone's bpm bounds and its share of the total. |

### Vitals

#### bp-trend

Blood pressure over time: each reading is a bar from diastolic to systolic, drawn over the systolic and diastolic ranges (green, yellow near each limit). Systolic and diastolic are judged separately; the reading is colored by the worse of the two: red out of range (triangle-down L low, triangle-up H high), yellow near a limit, green in range, grey when neither has a range. The ranges come from the data source via the sys_low/sys_high/dia_low/dia_high slots.

![bp-trend](docs/screenshots/bp-trend.png)

- Takes: `data` as rows `{time, systolic, diastolic, [warn_margin]}`
- Range slots, from the data source (null or left out = unknown, drawn grey): `sys_low`, `sys_high`, `dia_low`, `dia_high`
- Try it: `(health-chart-demo "bp-trend")`

#### vitals-dashboard

Five vitals on one time axis, each against its own range: heart rate, blood pressure (systolic and diastolic), temperature, SpO2 and respiratory rate. Each range is a band (green, yellow near each limit); readings are red out of range (triangle-down low, triangle-up high), yellow near a limit, green in range, grey when that metric has no range. The ranges come from the data source via the hr_/sbp_/dbp_/temp_/spo2_/rr_ low and high slots; a missing pair is grey no range.

![vitals-dashboard](docs/screenshots/vitals-dashboard.png)

- Takes: `data` as rows `{time, metric, value, [warn_low], [warn_high], [warn_margin]}`
- Range slots, from the data source (null or left out = unknown, drawn grey): `hr_low`, `hr_high`, `sbp_low`, `sbp_high`, `dbp_low`, `dbp_high`, `temp_low`, `temp_high`, `spo2_low`, `spo2_high`, `rr_low`, `rr_high`
- Try it: `(health-chart-demo "vitals-dashboard")`

#### vitals-trend

One vital sign over time against its normal range: the range as a band (green, yellow near each limit) and each reading colored red out of range, yellow near a limit, green in range, grey with no range, flagged L or H by shape and letter. The range comes from the data source via the low/high slots.

![vitals-trend](docs/screenshots/vitals-trend.png)

- Takes: `data` as rows `{time, value, [warn_low], [warn_high], [warn_margin]}`
- Range slots, from the data source (null or left out = unknown, drawn grey): `low`, `high`
- Try it: `(health-chart-demo "vitals-trend")`

### Heart and rhythm

#### ecg-strip

An ECG-style strip: millivolts against seconds over ECG paper (small boxes 0.04 s by 0.1 mV, large boxes 0.2 s by 0.5 mV). A drawing aid, not a diagnostic tool.

![ecg-strip](docs/screenshots/ecg-strip.png)

- Takes: `data` as rows `{t, mv}`
- Try it: `(health-chart-demo "ecg-strip")`

#### hrv-trend

Daily heart-rate variability (RMSSD) with a 7-day rolling mean and a personal baseline band (green, yellow near each edge); days below the baseline are red and flagged L, days above it red and flagged H. The baseline comes from the data via the low/high slots. Legend words: below baseline / near edge / within baseline / above baseline / no baseline.

![hrv-trend](docs/screenshots/hrv-trend.png)

- Takes: `data` as rows `{date, hrv, [warn_low], [warn_high], [warn_margin]}`
- Range slots, from the data source (null or left out = unknown, drawn grey): `low`, `high`
- Try it: `(health-chart-demo "hrv-trend")`

### Lab results

#### lab-change

Before and after for each analyte on its own reference range: a dumbbell from the earlier result (hollow) to the later one (filled) over the range bar (green, yellow near each limit). Each marker is colored by its own status (red out of range, yellow near a limit, green in range, grey with no range) and shaped by direction. The connecting line and the word at the right say how the result moved, in neutral colors: improved (nearer the range, or inside it nearer its middle), worsened, unchanged, or no range when no direction can be decided; this is not a health status.

![lab-change](docs/screenshots/lab-change.png)

- Takes: `data` as rows `{analyte, [unit], before, after, [ref_low], [ref_high], [opt_low], [opt_high], [warn_low], [warn_high], [warn_margin]}`
- Try it: `(health-chart-demo "lab-change")`

#### lab-panel

Small multiples: one compact trend per analyte, each on its own scale with its own reference range (from the panels table) as a band, green with yellow zones near each limit; every result is colored red out of range, yellow near a limit, green in range or grey with no range, and shaped by direction. The range is data, never a template default.

![lab-panel](docs/screenshots/lab-panel.png)

- Takes: `data` as rows `{time, analyte, value, [warn_low], [warn_high], [warn_margin]}`; `panels` as rows `{analyte, label, [unit], [low], [high], [warn_low], [warn_high], [warn_margin]}`
- Try it: `(health-chart-demo "lab-panel")`

#### lab-recency

How long ago each test was last drawn, against how often it is due: a bar of days since the last draw and a tick at the interval. Staleness is not a health status, so it is drawn in blues only: lighter within the interval, deeper when overdue (up to overdue_factor times the interval), darkest when long overdue, grey when never drawn; each state is also written next to its bar. The reference date as_of is supplied, never read from a clock.

![lab-recency](docs/screenshots/lab-recency.png)

- Takes: `data` as rows `{test, [last_drawn], interval_days}`
- Required slots: `as_of`
- Try it: `(health-chart-demo "lab-recency")`

#### lab-results

Latest result of many analytes, each placed within its own reference range: the range is the bar (green, yellow near each limit or outside the optimal range), the result a marker colored red out of range, yellow near a limit or outside the optimal range (suboptimal), green in range and grey when there is no range.

![lab-results](docs/screenshots/lab-results.png)

- Takes: `data` as rows `{analyte, value, [unit], [ref_low], [ref_high], [opt_low], [opt_high], [warn_low], [warn_high], [warn_margin]}`
- Try it: `(health-chart-demo "lab-results")`

#### lab-status-grid

A grid of analytes by draw date: each cell is filled with its status color at partial opacity (red out of range, yellow near a limit or, with an optimal range, outside it (suboptimal), green in range, grey with no range) and carries a glyph (low, near, suboptimal, in range, high, ?) and the value, judged against that row's own reference range. Ranges come from the data, either limit may be missing.

![lab-status-grid](docs/screenshots/lab-status-grid.png)

- Takes: `data` as rows `{time, analyte, value, [ref_low], [ref_high], [opt_low], [opt_high], [warn_low], [warn_high], [warn_margin]}`
- Try it: `(health-chart-demo "lab-status-grid")`

#### lab-trend

One lab analyte over time against its reference range: the range as a band (green, yellow near each limit), an optional optimal band inside it, and each result colored red out of the reference range, yellow near a limit or outside the optimal range (suboptimal), green in range, grey with no range, and flagged L or H by shape and letter.

![lab-trend](docs/screenshots/lab-trend.png)

- Takes: `data` as rows `{time, value, [warn_low], [warn_high], [warn_margin]}`
- Range slots, from the data source (null or left out = unknown, drawn grey): `low`, `high`, `opt_low`, `opt_high`
- Try it: `(health-chart-demo "lab-trend")`

#### lipid-panel

A lipid panel against goal lines: one bar per measure, a tick at its goal, an optional hollow marker for the prior draw. Each measure is judged against its own goal, a one-sided range: a 'below' goal has only an upper limit, an 'above' goal only a lower one. The bar is red only outside the reference limit (low means below an 'above' goal's reference limit, high above a 'below' goal's), yellow when the goal is missed but the reference limit is kept (suboptimal), green when the goal is met; a measure with no reference limit treats the goal as its limit: red when missed, yellow near it, green clear of it. The status is also written at the bar end. Goals and reference limits are data.

![lipid-panel](docs/screenshots/lipid-panel.png)

- Takes: `data` as rows `{analyte, value, [unit], goal, direction, [ref_limit], [prior], [warn_low], [warn_high], [warn_margin]}`
- Try it: `(health-chart-demo "lipid-panel")`

### Glucose and diabetes

#### agp

Ambulatory glucose profile: many days of readings folded onto one 24 hour day as the median line with the 25-75th and 5-95th percentile bands (neutral blues) and, when the data source supplies it, the target range as a green band. The profile itself is not judged, so it uses no red or yellow.

![agp](docs/screenshots/agp.png)

- Takes: `data` as rows `{time, glucose}`
- Range slots, from the data source (null or left out = unknown, drawn grey): `low`, `high`
- Try it: `(health-chart-demo "agp")`

#### cgm-day

A continuous glucose monitor day: the glucose line over 24 hours against the target range from the data source (band: green, yellow near each limit); readings are red out of range (triangle-down low, triangle-up high, letter L or H), yellow near a limit, green in range, grey with no range. Optional very low / very high limits are drawn as labelled dashed rules; a reading beyond one is red like any out-of-range reading but larger and flagged with its letter and !! (dense days are not lettered otherwise).

![cgm-day](docs/screenshots/cgm-day.png)

- Takes: `data` as rows `{time, glucose, [warn_low], [warn_high], [warn_margin]}`
- Range slots, from the data source (null or left out = unknown, drawn grey): `very_low`, `low`, `high`, `very_high`
- Try it: `(health-chart-demo "cgm-day")`

#### time-in-range

Time in range: the share of glucose readings very low, low, in range, high and very high per period (weeks, days, any label you give), computed from the raw readings against the four cut-offs from the data source (all required). Out-of-range shares are red (very low and very high solid, low and high tinted), in range is green. Shares have no warning margin, so there is no yellow. An optional target_pct draws a target tick on the in-range share.

![time-in-range](docs/screenshots/time-in-range.png)

- Takes: `data` as rows `{time, glucose, [period]}`
- Required slots: `very_low`, `low`, `high`, `very_high`
- Try it: `(health-chart-demo "time-in-range")`

### Trends against published categories (A1c, eGFR, BMI)

#### a1c-trend

HbA1c (%) over time against category bands bound from the data source (each band carries its own status: low, near, ok or high); bands are filled and readings colored and shaped by that status, with an optional personal target line.

![a1c-trend](docs/screenshots/a1c-trend.png)

- Takes: `data` as rows `{time, value}`; `bands` as rows `{label, low, high, status, [color]}`
- Try it: `(health-chart-demo "a1c-trend")`

#### egfr-trend

Estimated GFR (mL/min/1.73 m2) over time against category bands bound from the data source (each band carries its own status: low, near, ok or high); bands are filled and readings colored and shaped by that status, with an optional personal target line.

![egfr-trend](docs/screenshots/egfr-trend.png)

- Takes: `data` as rows `{time, value}`; `bands` as rows `{label, low, high, status, [color]}`
- Try it: `(health-chart-demo "egfr-trend")`

#### weight-bmi-trend

BMI over time, computed from weight and height, against category bands bound from the data source (each band carries its own status: low, near, ok or high); bands are filled and readings colored and shaped by that status; the weight is in the tooltip.

![weight-bmi-trend](docs/screenshots/weight-bmi-trend.png)

- Takes: `data` as rows `{time, weight_kg}`; `bands` as rows `{label, low, high, status, [color]}`
- Required slots: `height_m`
- Try it: `(health-chart-demo "weight-bmi-trend")`

### Fluids

#### fluid-balance

Fluid balance per day: intake bars up, output bars down, in millilitres, with the net balance marked and labelled; the totals are computed from the individual entries.

![fluid-balance](docs/screenshots/fluid-balance.png)

- Takes: `data` as rows `{time, kind, ml, [source]}`
- Try it: `(health-chart-demo "fluid-balance")`

### Medication

#### medication-timeline

Medication courses as neutral bars on a timeline, each scheduled dose marked taken (blue circle), late (light blue diamond) or missed (grey cross), with the adherence share per medication.

![medication-timeline](docs/screenshots/medication-timeline.png)

- Takes: `courses` as rows `{medication, start, end, [dose]}`; `doses` as rows `{medication, time, status}`
- Try it: `(health-chart-demo "medication-timeline")`

### Immunizations

#### immunization-timeline

Immunization history: one row per vaccine, doses given as blue circles, doses still due as grey diamonds and doses due before the as_of date as dark triangles labelled overdue (overdue is a scheduling state, not a health judgment).

![immunization-timeline](docs/screenshots/immunization-timeline.png)

- Takes: `data` as rows `{vaccine, date, [dose], status}`
- Required slots: `as_of`
- Try it: `(health-chart-demo "immunization-timeline")`

### Symptoms

#### symptom-diary

Symptom or pain diary: one row per symptom, one column per day, each cell shaded and numbered by the severity logged (0 none to 10 worst); a note rides in the tooltip.

![symptom-diary](docs/screenshots/symptom-diary.png)

- Takes: `data` as rows `{date, symptom, severity, [note]}`
- Try it: `(health-chart-demo "symptom-diary")`

### Cycle tracking

#### cycle-tracker

Menstrual cycle tracker: one row per cycle on a cycle-day axis, phases as labelled coloured segments and optional daily markers. The caller supplies every phase boundary; nothing is predicted.

![cycle-tracker](docs/screenshots/cycle-tracker.png)

- Takes: `data` as rows `{cycle, start_day, end_day, phase}`; `markers` (optional) as rows `{cycle, day, marker}`
- Try it: `(health-chart-demo "cycle-tracker")`

### Growth

#### growth-chart

Paediatric growth chart: percentile curves bound by the caller (bind published CDC or WHO curves; this package ships none) with the patient's measurements drawn over them. The example curves are synthetic.

![growth-chart](docs/screenshots/growth-chart.png)

- Takes: `data` as rows `{age, value}`; `curves` as rows `{age, percentile, value}`
- Try it: `(health-chart-demo "growth-chart")`

### Sleep

#### sleep-duration

Nightly sleep as stacked bars by stage, the time in bed in hours above each night and, when a goal is supplied, the sleep goal as a dashed line.

![sleep-duration](docs/screenshots/sleep-duration.png)

- Takes: `data` as rows `{date, stage, minutes}`
- Try it: `(health-chart-demo "sleep-duration")`

#### sleep-hypnogram

One night of sleep as a hypnogram: the stage (awake, REM, light, deep) over time, one segment per stage change.

![sleep-hypnogram](docs/screenshots/sleep-hypnogram.png)

- Takes: `data` as rows `{start, end, stage}`
- Try it: `(health-chart-demo "sleep-hypnogram")`

### Activity and fitness

#### activity-calendar

A calendar heatmap of a daily count such as steps: weeks as columns, weekdays as rows, color by value, a check mark on days that met the goal.

![activity-calendar](docs/screenshots/activity-calendar.png)

- Takes: `data` as rows `{date, steps}`
- Try it: `(health-chart-demo "activity-calendar")`

#### hr-zones

Time spent in each heart-rate zone as horizontal bars, with the zone's bpm bounds and its share of the total.

![hr-zones](docs/screenshots/hr-zones.png)

- Takes: `data` as rows `{zone, minutes, low, high}`
- Try it: `(health-chart-demo "hr-zones")`

## API

| Function | Does |
|---|---|
| `(health-chart-list-templates)` | every template as `(NAME :group G :doc D)` |
| `(health-chart-describe-template NAME)` | slots, the rows each table takes, rules, example, default sizes |
| `(health-chart-example NAME)` | synthetic bindings that render as is |
| `(health-chart-validate NAME BINDINGS)` | `t` or `health-chart-invalid-data` |
| `(health-chart-check NAME BINDINGS)` | `t` or `(:code :path :index :field :message)` |
| `(health-chart-render NAME BINDINGS &rest PROPS)` | a string: SVG or text. PROPS: `:backend` (`text`, `svg`, `auto`), `:width`/`:height` (text columns and rows, SVG pixels), `:pixel-width`/`:pixel-height`, `:title`, `:font` |
| `(health-chart-write NAME BINDINGS FILE)` | write SVG (or text for `.txt`) |
| `(health-chart-insert NAME BINDINGS)` | insert at point, as an image or text |
| `(health-chart-open NAME BINDINGS)` | a live eas view in a buffer (hover, crosshair, zoom, the eas agent verbs) |
| `(health-chart-demo NAME)` | open a template over its example |
| `(health-chart-read-bindings FILE-OR-JSON)` | parse bindings |
| `(health-chart-from-biomarker TEMPLATE ENVELOPE &rest OPTS)` | bindings from a `biomarker/v1` envelope (pure) |
| `(health-chart-status VALUE LOW HIGH &optional MARGIN WARN-LOW WARN-HIGH OPT-LOW OPT-HIGH)` | `low`, `near`, `suboptimal`, `ok`, `high` or `unknown` |

Errors are typed: `health-chart-unknown-template`, `health-chart-invalid-data`
and `health-chart-backend-error`, all under `health-chart-error`. `auto`
draws SVG in a graphical frame and text in a terminal
(`health-chart-backend`). Text output is deterministic and carries eas's
hover help and datum properties, so an agent can read a chart as text.

The package also registers eas transforms through eas's public registry:
`time-of-day-percentiles` (the percentile bands of `agp`), `health-status`
and `health-band-status` (the color rule above, which the templates call).

## Adding a template

A template is `templates/NAME.json` (Vega-Lite plus an `x-eas` block of
slots) and `examples/NAME.data.json` (synthetic bindings). Its
`x-eas.health` block names the group, default sizes and what each table
takes; `src/health-chart-validate.el` documents the field types. `make
goldens` writes the goldens and `make test` then breaks every declared field
and expects the right code and path. See `AGENTS.md` and
`docs/design/render-only.md`.

## Tests

```sh
make test EAS=/path/to/eas.el        # ERT: validation, API, the color rule, the adapter, goldens for text and SVG
make compile EAS=/path/to/eas.el     # byte-compile, warnings are errors
make checkdoc
make screenshots EAS=/path/to/eas.el # docs/screenshots/*.png (needs rsvg-convert)
```

Goldens live in `test/golden/text` and `test/golden/svg`;
`make goldens` rewrites them, then review the diff.

## License

See [LICENSE](LICENSE).
