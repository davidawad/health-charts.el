# health-chart: panel chart, svg, generated from a template
set encoding utf8
set terminal svg size 720,558 dynamic noenhanced font 'DejaVu Sans,12' background '#fcfcfb'
set datafile separator "\t"
set datafile columnheaders
# health-chart panel: small multiples, one compact time series per
# marker on its own y scale, reference and optimal bands shaded, points
# by status (shape + color; glyph and word in the key), the latest value
# and status above each cell.  The backend has already chosen the
# terminal, the output and a tab-separated datafile with column headers.

$data << EOD
person	marker	label	date	value	unit	value_label	status	glyph	status_label	color	rgb	shape	pt	ref_low	ref_high	opt_low	opt_high	series	latest	panel	panel_index	latest_label	y_min	y_max	ref_y	ref_y2	opt_y	opt_y2
alex	ldl-c	LDL-C	2021-11-08	162	mg/dL	162 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	alex	0	LDL-C · mg/dL	1	76 mg/dL  ◐ suboptimal	0	174.96	0	100	0	70
alex	ldl-c	LDL-C	2022-05-16	151	mg/dL	151 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	alex	0	LDL-C · mg/dL	1	76 mg/dL  ◐ suboptimal	0	174.96	0	100	0	70
alex	ldl-c	LDL-C	2022-11-14	138	mg/dL	138 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	alex	0	LDL-C · mg/dL	1	76 mg/dL  ◐ suboptimal	0	174.96	0	100	0	70
alex	ldl-c	LDL-C	2023-06-05	121	mg/dL	121 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	alex	0	LDL-C · mg/dL	1	76 mg/dL  ◐ suboptimal	0	174.96	0	100	0	70
alex	ldl-c	LDL-C	2024-01-15	104	mg/dL	104 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	alex	0	LDL-C · mg/dL	1	76 mg/dL  ◐ suboptimal	0	174.96	0	100	0	70
alex	ldl-c	LDL-C	2024-08-12	92	mg/dL	92 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	100	NaN	70	alex	0	LDL-C · mg/dL	1	76 mg/dL  ◐ suboptimal	0	174.96	0	100	0	70
alex	ldl-c	LDL-C	2025-03-10	84	mg/dL	84 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	100	NaN	70	alex	0	LDL-C · mg/dL	1	76 mg/dL  ◐ suboptimal	0	174.96	0	100	0	70
alex	ldl-c	LDL-C	2025-09-15	76	mg/dL	76 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	100	NaN	70	alex	1	LDL-C · mg/dL	1	76 mg/dL  ◐ suboptimal	0	174.96	0	100	0	70
alex	hdl-c	HDL-C	2021-11-08	38	mg/dL	38 mg/dL	low	▼	▼ low	#d03b3b	13646651	triangle-down	11	40	NaN	60	NaN	alex	0	HDL-C · mg/dL	2	61 mg/dL  ● optimal	36.16	62.84	40	62.84	60	62.84
alex	hdl-c	HDL-C	2022-05-16	41	mg/dL	41 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	alex	0	HDL-C · mg/dL	2	61 mg/dL  ● optimal	36.16	62.84	40	62.84	60	62.84
alex	hdl-c	HDL-C	2022-11-14	44	mg/dL	44 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	alex	0	HDL-C · mg/dL	2	61 mg/dL  ● optimal	36.16	62.84	40	62.84	60	62.84
alex	hdl-c	HDL-C	2023-06-05	47	mg/dL	47 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	alex	0	HDL-C · mg/dL	2	61 mg/dL  ● optimal	36.16	62.84	40	62.84	60	62.84
alex	hdl-c	HDL-C	2024-01-15	52	mg/dL	52 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	alex	0	HDL-C · mg/dL	2	61 mg/dL  ● optimal	36.16	62.84	40	62.84	60	62.84
alex	hdl-c	HDL-C	2024-08-12	55	mg/dL	55 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	alex	0	HDL-C · mg/dL	2	61 mg/dL  ● optimal	36.16	62.84	40	62.84	60	62.84
alex	hdl-c	HDL-C	2025-03-10	58	mg/dL	58 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	40	NaN	60	NaN	alex	0	HDL-C · mg/dL	2	61 mg/dL  ● optimal	36.16	62.84	40	62.84	60	62.84
alex	hdl-c	HDL-C	2025-09-15	61	mg/dL	61 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	40	NaN	60	NaN	alex	1	HDL-C · mg/dL	2	61 mg/dL  ● optimal	36.16	62.84	40	62.84	60	62.84
alex	vitamin-d	Vitamin D	2021-11-08	22	ng/mL	22 ng/mL	low	▼	▼ low	#d03b3b	13646651	triangle-down	11	30	100	40	60	alex	0	Vitamin D · ng/mL	3	55 ng/mL  ● optimal	18.96	63.04	30	63.04	40	60
alex	vitamin-d	Vitamin D	2022-05-16	26	ng/mL	26 ng/mL	low	▼	▼ low	#d03b3b	13646651	triangle-down	11	30	100	40	60	alex	0	Vitamin D · ng/mL	3	55 ng/mL  ● optimal	18.96	63.04	30	63.04	40	60
alex	vitamin-d	Vitamin D	2022-11-14	34	ng/mL	34 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	100	40	60	alex	0	Vitamin D · ng/mL	3	55 ng/mL  ● optimal	18.96	63.04	30	63.04	40	60
alex	vitamin-d	Vitamin D	2023-06-05	41	ng/mL	41 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	alex	0	Vitamin D · ng/mL	3	55 ng/mL  ● optimal	18.96	63.04	30	63.04	40	60
alex	vitamin-d	Vitamin D	2024-01-15	38	ng/mL	38 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	100	40	60	alex	0	Vitamin D · ng/mL	3	55 ng/mL  ● optimal	18.96	63.04	30	63.04	40	60
alex	vitamin-d	Vitamin D	2024-08-12	47	ng/mL	47 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	alex	0	Vitamin D · ng/mL	3	55 ng/mL  ● optimal	18.96	63.04	30	63.04	40	60
alex	vitamin-d	Vitamin D	2025-03-10	52	ng/mL	52 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	alex	0	Vitamin D · ng/mL	3	55 ng/mL  ● optimal	18.96	63.04	30	63.04	40	60
alex	vitamin-d	Vitamin D	2025-09-15	55	ng/mL	55 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	alex	1	Vitamin D · ng/mL	3	55 ng/mL  ● optimal	18.96	63.04	30	63.04	40	60
alex	tsh	TSH	2021-11-08	1.8	mIU/L	1.8 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	alex	0	TSH · mIU/L	4	2.1 mIU/L  ● optimal	1.744	2.556	1.744	2.556	1.744	2.5
alex	tsh	TSH	2022-05-16	2.1	mIU/L	2.1 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	alex	0	TSH · mIU/L	4	2.1 mIU/L  ● optimal	1.744	2.556	1.744	2.556	1.744	2.5
alex	tsh	TSH	2022-11-14	1.9	mIU/L	1.9 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	alex	0	TSH · mIU/L	4	2.1 mIU/L  ● optimal	1.744	2.556	1.744	2.556	1.744	2.5
alex	tsh	TSH	2023-06-05	2.4	mIU/L	2.4 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	alex	0	TSH · mIU/L	4	2.1 mIU/L  ● optimal	1.744	2.556	1.744	2.556	1.744	2.5
alex	tsh	TSH	2024-01-15	2.2	mIU/L	2.2 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	alex	0	TSH · mIU/L	4	2.1 mIU/L  ● optimal	1.744	2.556	1.744	2.556	1.744	2.5
alex	tsh	TSH	2024-08-12	2.0	mIU/L	2 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	alex	0	TSH · mIU/L	4	2.1 mIU/L  ● optimal	1.744	2.556	1.744	2.556	1.744	2.5
alex	tsh	TSH	2025-03-10	2.3	mIU/L	2.3 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	alex	0	TSH · mIU/L	4	2.1 mIU/L  ● optimal	1.744	2.556	1.744	2.556	1.744	2.5
alex	tsh	TSH	2025-09-15	2.1	mIU/L	2.1 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	alex	1	TSH · mIU/L	4	2.1 mIU/L  ● optimal	1.744	2.556	1.744	2.556	1.744	2.5
EOD

array PM = ['ldl-c', 'hdl-c', 'vitamin-d', 'tsh']
array PT = ['LDL-C · mg/dL', 'HDL-C · mg/dL', 'Vitamin D · ng/mL', 'TSH · mIU/L']
array PL = ['76 mg/dL  ◐ suboptimal', '61 mg/dL  ● optimal', '55 ng/mL  ● optimal', '2.1 mIU/L  ● optimal']
array PY0 = [0, 36.16, 18.96, 1.744]
array PY1 = [174.96, 62.84, 63.04, 2.556]
array PR0 = [0, 40, 30, 1.744]
array PR1 = [100, 62.84, 63.04, 2.556]
array PO0 = [0, 60, 40, 1.744]
array PO1 = [70, 62.84, 60, 2.5]
array PC = [1, 2, 3, 1]
array PR = [1, 1, 1, 2]
array LK = ['optimal', 'suboptimal', 'low', 'high']
array LL = ['● optimal', '◐ suboptimal', '▼ low', '▲ high']
array LC = ['#0ca30c', '#e09a00', '#d03b3b', '#d03b3b']
array LP = [7, 13, 11, 9]
array XT = [1640995200, 1704067200]
array XL = ['2022', '2024']
text = ('svg' eq 'text')
ncol = 3
nrow = 2

# Figure geometry in screen fractions, from the spec's pixel size: the
# title block on top, the key below, then one cell per panel with room
# for its header (title, latest value) above and date labels below.
W = 720.0
H = 558.0
top = 1 - 84 / H
bottom = 64 / H
left = 0.015
right = 0.985
if (text) {
  th = 9 * nrow + 3
  set terminal dumb noenhanced size 72, th
  H = th; W = 72
  top = 1 - 1.5 / H; bottom = 1.5 / H; left = 0.0; right = 1.0
}
colw = (right - left) / ncol
rowh = (top - bottom) / nrow
padtop = (text ? 2.0 : 56) / H
padbot = (text ? 1.0 : 36) / H
padl = (text ? 7.0 : 46) / W
padr = (text ? 2.0 : 20) / W

set label 1 'Panel · alex' at screen 0.015, screen 1 offset 0,-1.3 left font 'DejaVu Sans'.' Bold,16' textcolor rgb '#0b0b0b'
set label 2 '4 markers, 2021-11-08 to 2025-09-15' at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb '#52514e'
if (text) { unset label 2; set label 1 at screen 0, screen 1 offset 0,-0.5 }

set border 3 linecolor rgb '#c3c2b7'
set tics nomirror textcolor rgb '#52514e' font ',9.5'
set grid ytics linetype 1 linecolor rgb '#e1e0d9' linewidth 1
set grid noxtics
unset key
set xdata time
set timefmt '%Y-%m-%d'
set xrange ['2021-09-13':'2025-11-10']
set xtics ()
do for [i=1:|XT|] { set xtics add (XL[i] XT[i]) }
set ytics scale 0.5
set xtics scale 0.5
set ylabel
if (text) {
  unset grid; set ytics scale 0; set xtics scale 0
  # short date labels so a narrow cell's ticks stay apart: '22 or Nov
  set xtics ()
  do for [i=1:|XT|] { set xtics add ((strlen(XL[i]) == 4 ? "'" . XL[i][3:4] : XL[i][1:3]) XT[i]) }
}

set multiplot
do for [i=1:|PM|] {
  x0 = left + (PC[i] - 1) * colw
  y1 = top - (PR[i] - 1) * rowh
  set lmargin at screen x0 + padl
  set rmargin at screen x0 + colw - padr
  set tmargin at screen y1 - padtop
  set bmargin at screen y1 - rowh + padbot
  set yrange [PY0[i]:PY1[i]]
  # about four y ticks on a 1-2-5 step
  r = (PY1[i] - PY0[i]) / 4.0
  e = 10.0 ** floor(log10(r))
  f = r / e
  step = (f < 1.5 ? 1 : f < 3 ? 2 : f < 7 ? 5 : 10) * e
  set ytics ceil(PY0[i] / step) * step, step
  unset object 1
  unset object 2
  if (!text && PR0[i] == PR0[i]) {
    set object 1 rect from graph 0, first PR0[i] to graph 1, first PR1[i] \
        behind fillcolor rgb '#b8b7ad' fillstyle transparent solid 0.28 noborder
  }
  if (!text && PO0[i] == PO0[i]) {
    set object 2 rect from graph 0, first PO0[i] to graph 1, first PO1[i] \
        behind fillcolor rgb '#0ca30c' fillstyle transparent solid 0.14 noborder
  }
  if (text) {
    set label 11 PT[i] at graph 0, graph 1 offset -5,1 left
    plot $data using 'date':(strcol('marker') eq PM[i] ? column('value') : NaN) with lines linetype 1, \
         $data using 'date':(strcol('marker') eq PM[i] ? column('value') : NaN):'glyph' with labels
  } else {
    set label 11 PT[i] at graph 0, graph 1 offset -0.5,2.1 left font ('DejaVu Sans' . ' Bold,11.5') textcolor rgb '#0b0b0b'
    set label 12 PL[i] at graph 1, graph 1 offset 0,0.9 right font ',10.5' textcolor rgb '#52514e'
    plot \
      $data using 'date':(strcol('marker') eq PM[i] ? column('value') : NaN) \
          with lines linewidth 1.6 linecolor rgb '#898781', \
      for [k=1:|LK|] $data using 'date':(strcol('marker') eq PM[i] && strcol('status') eq LK[k] ? column('value') : NaN) \
          with points pointtype LP[k] pointsize 1.1 linecolor rgb LC[k]
  }
  if (i == 1) { unset label 1; unset label 2 }
}

# The key alone, in a full-width strip at the bottom of the figure.
if (text) {
  key = ''
  do for [i=1:|LL|] { key = key . LL[i] . '   ' }
  set label 3 key at screen 0, screen 0 offset 1,0.5 left
} else {
  unset label 11; unset label 12; unset label 3
}
unset object 1; unset object 2
unset border; unset tics; unset grid; unset xdata
set lmargin at screen 0.03; set rmargin at screen 0.97
set tmargin at screen bottom - 8 / H; set bmargin at screen 0.005
set xrange [0:1]; set yrange [0:1]
set key inside center center horizontal Left reverse noautotitle textcolor rgb '#52514e' \
    samplen 1.5 spacing 1.2 width 2
if (text) {
  unset key
  set tmargin at screen 0.5 / H
  plot 2 notitle
} else {
  plot 2 with lines linecolor rgb '#fcfcfb' notitle, \
    keyentry with boxes fillcolor rgb '#b8b7ad' fillstyle transparent solid 0.28 \
        noborder title 'reference range', \
    keyentry with boxes fillcolor rgb '#0ca30c' fillstyle transparent solid 0.14 \
        noborder title 'optimal range', \
    for [k=1:|LK|] keyentry with points pointtype LP[k] pointsize 1.3 linecolor rgb LC[k] title LL[k]
}
unset multiplot
