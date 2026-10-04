# health-chart: dual chart, svg, generated from a template
set encoding utf8
set terminal svg size 720,360 dynamic noenhanced font 'DejaVu Sans,12' background '#fcfcfb'
set datafile separator "\t"
set datafile columnheaders
# health-chart dual: two related markers over time, one per axis (left
# solid, right dashed; axis titles in the marker's color), points by
# status (shape + color, glyph and word in the key), each marker's upper
# reference limit dotted on its own axis.  The backend has already chosen
# the terminal, the output and a tab-separated datafile with column
# headers.

$data << EOD
person	marker	label	date	value	unit	value_label	status	glyph	status_label	color	rgb	shape	pt	ref_low	ref_high	opt_low	opt_high	series	series_label	series_color	axis	latest
alex	glucose	Glucose	2021-11-08	108	mg/dL	108 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	70	99	72	90	glucose	Glucose (left axis)	#2a78d6	left	0
alex	glucose	Glucose	2022-05-16	104	mg/dL	104 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	70	99	72	90	glucose	Glucose (left axis)	#2a78d6	left	0
alex	glucose	Glucose	2022-11-14	101	mg/dL	101 mg/dL	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	70	99	72	90	glucose	Glucose (left axis)	#2a78d6	left	0
alex	glucose	Glucose	2023-06-05	97	mg/dL	97 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	70	99	72	90	glucose	Glucose (left axis)	#2a78d6	left	0
alex	glucose	Glucose	2024-01-15	94	mg/dL	94 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	70	99	72	90	glucose	Glucose (left axis)	#2a78d6	left	0
alex	glucose	Glucose	2024-08-12	92	mg/dL	92 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	70	99	72	90	glucose	Glucose (left axis)	#2a78d6	left	0
alex	glucose	Glucose	2025-03-10	96	mg/dL	96 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	70	99	72	90	glucose	Glucose (left axis)	#2a78d6	left	0
alex	glucose	Glucose	2025-09-15	89	mg/dL	89 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	70	99	72	90	glucose	Glucose (left axis)	#2a78d6	left	1
alex	hba1c	HbA1c	2021-11-08	5.9	%	5.9 %	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	4.0	5.6	NaN	5.3	hba1c	HbA1c (right axis)	#4a3aa7	right	0
alex	hba1c	HbA1c	2022-05-16	5.8	%	5.8 %	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	4.0	5.6	NaN	5.3	hba1c	HbA1c (right axis)	#4a3aa7	right	0
alex	hba1c	HbA1c	2022-11-14	5.7	%	5.7 %	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	4.0	5.6	NaN	5.3	hba1c	HbA1c (right axis)	#4a3aa7	right	0
alex	hba1c	HbA1c	2023-06-05	5.6	%	5.6 %	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	4.0	5.6	NaN	5.3	hba1c	HbA1c (right axis)	#4a3aa7	right	0
alex	hba1c	HbA1c	2024-01-15	5.5	%	5.5 %	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	4.0	5.6	NaN	5.3	hba1c	HbA1c (right axis)	#4a3aa7	right	0
alex	hba1c	HbA1c	2024-08-12	5.4	%	5.4 %	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	4.0	5.6	NaN	5.3	hba1c	HbA1c (right axis)	#4a3aa7	right	0
alex	hba1c	HbA1c	2025-03-10	5.3	%	5.3 %	optimal	●	● optimal	#0ca30c	828172	circle	7	4.0	5.6	NaN	5.3	hba1c	HbA1c (right axis)	#4a3aa7	right	0
alex	hba1c	HbA1c	2025-09-15	5.3	%	5.3 %	optimal	●	● optimal	#0ca30c	828172	circle	7	4.0	5.6	NaN	5.3	hba1c	HbA1c (right axis)	#4a3aa7	right	1
EOD

array LK = ['optimal', 'suboptimal', 'high']
array LL = ['● optimal', '◐ suboptimal', '▲ high']
array LC = ['#0ca30c', '#e09a00', '#d03b3b']
array LP = [7, 13, 9]
array XT = [1640995200, 1672531200, 1704067200, 1735689600]
array XL = ['2022', '2023', '2024', '2025']
array TV = [99, 5.6]
array TA = ['left', 'right']
array TL = ['Glucose ≤99', 'HbA1c ≤5.6']
array TC = ['#2a78d6', '#4a3aa7']
text = ('svg' eq 'text')

set label 1 'Glucose · HbA1c · alex' at screen 0.015, screen 1 offset 0,-1.3 left font 'DejaVu Sans'.' Bold,16' textcolor rgb '#0b0b0b'
set label 2 'latest: Glucose 89 mg/dL  ● optimal · HbA1c 5.3 %  ● optimal' at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb '#52514e'
set tmargin 5
set rmargin 9
set lmargin 10
set border 11 linecolor rgb '#c3c2b7'
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
set yrange [66.96:111.04]
set y2range [5.252:5.948]
set ytics nomirror textcolor rgb '#2a78d6'
set y2tics nomirror textcolor rgb '#4a3aa7'
set ylabel 'Glucose (mg/dL)' textcolor rgb '#2a78d6' font 'DejaVu Sans'.' Bold,12'
set y2label 'HbA1c (%)' textcolor rgb '#4a3aa7' font 'DejaVu Sans'.' Bold,12'

do for [i=1:|TV|] {
  if (TA[i] eq 'left') {
    set arrow i from graph 0, first TV[i] to graph 1, first TV[i] nohead dashtype 3 linewidth 1.5 linecolor rgb TC[i]
    set label 10+i TL[i] at graph 0, first TV[i] offset 0.8,0.7 left font ',10.5' textcolor rgb TC[i]
  } else {
    set arrow i from graph 0, second TV[i] to graph 1, second TV[i] nohead dashtype 3 linewidth 1.5 linecolor rgb TC[i]
    set label 10+i TL[i] at graph 0, second TV[i] offset 0.8,0.7 left font ',10.5' textcolor rgb TC[i]
  }
}

plot \
  $data using 'date':(strcol('axis') eq 'left' ? column('value') : NaN) axes x1y1 with lines \
      linewidth 3 linecolor rgb '#2a78d6' notitle, \
  $data using 'date':(strcol('axis') eq 'right' ? column('value') : NaN) axes x1y2 with lines \
      linewidth 3 dashtype 2 linecolor rgb '#4a3aa7' notitle, \
  for [i=1:|LK|] $data using 'date':(strcol('axis') eq 'left' && strcol('status') eq LK[i] ? column('value') : NaN) \
      axes x1y1 with points pointtype LP[i] pointsize 1.6 linecolor rgb LC[i] title LL[i], \
  for [i=1:|LK|] $data using 'date':(strcol('axis') eq 'right' && strcol('status') eq LK[i] ? column('value') : NaN) \
      axes x1y2 with points pointtype LP[i] pointsize 1.6 linecolor rgb LC[i] notitle
