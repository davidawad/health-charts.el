# health-chart: lollipop chart, svg, generated from a template
set encoding utf8
set terminal svg size 720,360 dynamic noenhanced font 'DejaVu Sans,12' background '#fcfcfb'
set datafile separator "\t"
set datafile columnheaders
# health-chart lollipop: one marker's draws as stems from its target limit
# to the value, status shapes at the tips (glyph and word in the key),
# each labeled with its distance past the limit.  The backend has already
# chosen the terminal, the output and a tab-separated datafile with
# column headers.

$data << EOD
person	marker	label	date	value	unit	value_label	status	glyph	status_label	color	rgb	shape	pt	ref_low	ref_high	opt_low	opt_high	series	latest	base	gap	gap_label
alex	hscrp	hs-CRP	2021-11-08	4.2	mg/L	4.2 mg/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	3.0	NaN	1.0	alex	0	1	3.2	+3.2
alex	hscrp	hs-CRP	2022-05-16	3.6	mg/L	3.6 mg/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	3.0	NaN	1.0	alex	0	1	2.6	+2.6
alex	hscrp	hs-CRP	2022-11-14	2.8	mg/L	2.8 mg/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	3.0	NaN	1.0	alex	0	1	1.8	+1.8
alex	hscrp	hs-CRP	2023-06-05	2.1	mg/L	2.1 mg/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	3.0	NaN	1.0	alex	0	1	1.1	+1.1
alex	hscrp	hs-CRP	2024-01-15	1.6	mg/L	1.6 mg/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	3.0	NaN	1.0	alex	0	1	0.6	+0.6
alex	hscrp	hs-CRP	2024-08-12	1.2	mg/L	1.2 mg/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	3.0	NaN	1.0	alex	0	1	0.2	+0.2
alex	hscrp	hs-CRP	2025-03-10	0.9	mg/L	0.9 mg/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0	3.0	NaN	1.0	alex	0	1	-0.1	−0.1
alex	hscrp	hs-CRP	2025-09-15	0.8	mg/L	0.8 mg/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0	3.0	NaN	1.0	alex	1	1	-0.2	−0.2
EOD

array LK = ['optimal', 'suboptimal', 'high']
array LL = ['● optimal', '◐ suboptimal', '▲ high']
array LC = ['#0ca30c', '#e09a00', '#d03b3b']
array LP = [7, 13, 9]
array XT = [1640995200, 1672531200, 1704067200, 1735689600]
array XL = ['2022', '2023', '2024', '2025']
text = ('svg' eq 'text')

set label 1 'hs-CRP · alex' at screen 0.015, screen 1 offset 0,-1.3 left font 'DejaVu Sans'.' Bold,16' textcolor rgb '#0b0b0b'
set label 2 'latest 0.8 mg/L on 2025-09-15 · ● optimal · stems run from the optimal limit 1 mg/L' at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb '#52514e'
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
set yrange [0:5.023]
set ylabel 'mg/L' textcolor rgb '#52514e'

if (!text && 0 == 0) {
  set object 1 rect from graph 0, first 0 to graph 1, first 3 \
      behind fillcolor rgb '#b8b7ad' fillstyle transparent solid 0.28 noborder
}
if (!text && 0 == 0) {
  set object 2 rect from graph 0, first 0 to graph 1, first 1 \
      behind fillcolor rgb '#0ca30c' fillstyle transparent solid 0.14 noborder
}
set arrow 1 from graph 0, first 1 to graph 1, first 1 \
    nohead dashtype 2 linewidth 1.5 linecolor rgb '#52514e' front
set label 3 'optimal limit 1 mg/L' at graph 1, first 1 \
    offset -0.8,0.7 right font ',10.5' textcolor rgb '#52514e'

plot \
  keyentry with boxes \
      fillcolor rgb '#b8b7ad' fillstyle transparent solid 0.28 noborder \
      title 'reference 0–3', \
  keyentry with boxes \
      fillcolor rgb '#0ca30c' fillstyle transparent solid 0.14 noborder \
      title 'optimal ≤1', \
  $data using 'date':'base':(0):'gap':'rgb' with vectors nohead linewidth 3 linecolor rgb variable notitle, \
  for [i=1:|LK|] $data using 'date':(strcol('status') eq LK[i] ? column('value') : NaN) \
      with points pointtype LP[i] pointsize 1.8 linecolor rgb LC[i] title LL[i], \
  $data using 'date':(column('gap') >= 0 ? column('value') : NaN):'gap_label' \
      with labels center offset 0,1.4 textcolor rgb '#0b0b0b' notitle, \
  $data using 'date':(column('gap') < 0 ? column('value') : NaN):'gap_label' \
      with labels center offset 0,-1.4 textcolor rgb '#0b0b0b' notitle
