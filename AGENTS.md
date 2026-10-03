# AGENTS.md — health-chart.el

Standalone, publishable Emacs package: every biomarker chart kind
(time series with reference/optimal bands, small multiples, sparkline
table, range bars, out-of-range heatmap, multi-person overlay, change
bars) as text or SVG from plain Lisp data or the biomarker CLI.
README.md is the full reference.

## Driving it

Ask the package; don't read source to learn its state.

1. Discover: `(health-chart-describe)` — kinds, shapes, statuses, the
   data source, entry points by verb. From a shell:
   `bin/health-chart describe`.
2. Learn a kind's input: `(health-chart-describe-kind 'bullet)` or
   `bin/health-chart example bullet` (a spec `render` accepts as-is).
3. Check data: `(health-chart-validate KIND DATA)`; a failure names the
   bad element's `:index`.
4. Plan: `(health-chart-explain KIND DATA &rest PROPS)` gives the exact
   renderer and args `health-chart-plot` will use, why that backend, and
   a data summary. Never draws or fetches.
5. Render: `health-chart-plot` / `-plot-spec`. Prefer `:backend 'text`
   to read a chart yourself; the text renderers are deterministic.
6. Fetch: `health-chart-source-query` / `-trend` / `-latest` / `-flag`
   go through `health-chart-source-function`; use
   `health-chart-source-static` to work without the CLI.
7. Health: `(health-chart-doctor-checks)` — rows
   `(:name :status pass|fail|skip :detail :remediation)`.

## Changing it

- `make test` (offline, no display, no biomarker install) and
  `make compile` (warnings are errors) must pass; so must
  `make checkdoc` and `make lint PACKAGE_LINT=<dir>`. Golden fixtures:
  regenerate with `HEALTH_CHART_UPDATE_GOLDEN=1 make test` and review
  the diff.
- New chart kind: a model in -model if it needs one, renderers in -text
  and -svg, then one `health-chart-kinds` entry (or
  `health-chart-register-kind`). The doctor and `describe` pick it up;
  add golden fixtures.
- The biomarker wire format lives only in health-chart-source.el
  (`health-chart-source-fields`, `-list-keys`, `-cli-args`). Nothing
  else may know JSON member names or CLI flags.
- Errors: `define-error` under `health-chart-error`, data
  `(MESSAGE :code CODE ...)`, message says how to fix it. Never
  message-and-return-nil.
- Status is never color alone: every status shows its glyph and word.
- Synthetic data only, in code, tests and docs.
