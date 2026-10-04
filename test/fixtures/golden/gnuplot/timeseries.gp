# health-chart: timeseries chart, svg, generated from a template
set encoding utf8
set terminal svg size 720,360 dynamic noenhanced font 'DejaVu Sans,12' background '#fcfcfb'
set datafile separator "\t"
set datafile columnheaders
# health-chart timeseries: one marker over time, reference and optimal
# bands shaded, points by status (shape + color, glyph and word in the
# key), latest value annotated.  The backend has already chosen the
# terminal, the output and a tab-separated datafile with column headers.

$data << EOD
person	marker	label	date	value	unit	value_label	status	glyph	status_label	color	rgb	shape	pt	ref_low	ref_high	opt_low	opt_high	series	latest
alex	ldl-c	LDL-C	2021-11-08	162	mg/dL	162 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	alex	0
alex	ldl-c	LDL-C	2022-05-16	151	mg/dL	151 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	alex	0
alex	ldl-c	LDL-C	2022-11-14	138	mg/dL	138 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	alex	0
alex	ldl-c	LDL-C	2023-06-05	121	mg/dL	121 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	alex	0
alex	ldl-c	LDL-C	2024-01-15	104	mg/dL	104 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	100	NaN	70	alex	0
alex	ldl-c	LDL-C	2024-08-12	92	mg/dL	92 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	100	NaN	70	alex	0
alex	ldl-c	LDL-C	2025-03-10	84	mg/dL	84 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	100	NaN	70	alex	0
alex	ldl-c	LDL-C	2025-09-15	76	mg/dL	76 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	100	NaN	70	alex	1
EOD
$latest << EOD
date	value	text	status_label	color
2025-09-15	76	latest 76 mg/dL	◐ suboptimal	#e09a00
EOD

array LK = ['suboptimal', 'high']
array LL = ['◐ suboptimal', '▲ high']
array LC = ['#e09a00', '#d03b3b']
array LP = [13, 9]
array XT = [1640995200, 1672531200, 1704067200, 1735689600]
array XL = ['2022', '2023', '2024', '2025']
text = ('svg' eq 'text')

set label 1 'LDL-C · alex' at screen 0.015, screen 1 offset 0,-1.3 left font 'DejaVu Sans'.' Bold,16' textcolor rgb '#0b0b0b'
set label 2 'latest 76 mg/dL on 2025-09-15 · ◐ suboptimal' at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb '#52514e'
set tmargin 5
set rmargin 4
set border 3 linecolor rgb '#c3c2b7'
set tics nomirror textcolor rgb '#52514e'
set grid ytics linetype 1 linecolor rgb '#e1e0d9' linewidth 1
set grid noxtics
set key outside bottom center horizontal Left reverse noautotitle textcolor rgb '#52514e' samplen 1.5 spacing 1.2 width 1

if (text) { unset grid; set tmargin 4 }

set xdata time
set timefmt '%Y-%m-%d'
set xrange ['2021-09-13':'2025-11-10']
set xtics ()
do for [i=1:|XT|] { set xtics add (XL[i] XT[i]) }
set yrange [0:174.96]
set ylabel 'mg/dL' textcolor rgb '#52514e'

if (!text && 0 == 0) {
  set object 1 rect from graph 0, first 0 to graph 1, first 100 \
      behind fillcolor rgb '#b8b7ad' fillstyle transparent solid 0.28 noborder
}
if (!text && 0 == 0) {
  set object 2 rect from graph 0, first 0 to graph 1, first 70 \
      behind fillcolor rgb '#0ca30c' fillstyle transparent solid 0.14 noborder
}

plot \
  keyentry with boxes \
      fillcolor rgb '#b8b7ad' fillstyle transparent solid 0.28 noborder \
      title 'reference 0–100', \
  keyentry with boxes \
      fillcolor rgb '#0ca30c' fillstyle transparent solid 0.14 noborder \
      title 'optimal ≤70', \
  $data using 'date':'value' with lines linewidth 2 linecolor rgb '#898781' notitle, \
  for [i=1:|LK|] $data using 'date':(strcol('status') eq LK[i] ? column('value') : NaN) \
      with points pointtype LP[i] pointsize 1.6 linecolor rgb LC[i] title LL[i], \
  $latest using 'date':'value':'text' with labels right offset -1,1.2 font 'DejaVu Sans'.' Bold,12' \
      textcolor rgb '#0b0b0b' notitle
