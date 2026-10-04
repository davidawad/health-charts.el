# health-chart: delta chart, svg, generated from a template
set encoding utf8
set terminal svg size 720,520 dynamic noenhanced font 'DejaVu Sans,12' background '#fcfcfb'
set datafile separator "\t"
set datafile columnheaders
# health-chart delta: percent change per marker between two draws,
# diverging bars from 0 colored by verdict (glyph and word in the key),
# each bar labeled with its change and its before and after values.
# The backend has already chosen the terminal, the output and a
# tab-separated datafile with column headers.

$data << EOD
index	marker	label	unit	before	after	change	pct	pct_label	value_label	side	verdict	glyph	verdict_label	color	rgb	text
1	ldl-c	LDL-C	mg/dL	84	76	-8	-9.5	-9.5%	84 → 76 mg/dL	neg	improved	✔	✔ improved	#0ca30c	828172	-9.5% ✔
2	hdl-c	HDL-C	mg/dL	58	61	3	5.2	+5.2%	58 → 61 mg/dL	pos	improved	✔	✔ improved	#0ca30c	828172	+5.2% ✔
3	triglycerides	Triglycerides	mg/dL	96	88	-8	-8.3	-8.3%	96 → 88 mg/dL	neg	on-target	●	● on-target	#2a78d6	2783446	-8.3% ●
4	apob	ApoB	mg/dL	76	72	-4	-5.3	-5.3%	76 → 72 mg/dL	neg	on-target	●	● on-target	#2a78d6	2783446	-5.3% ●
5	lpa	Lp(a)	nmol/L	149	144	-5	-3.4	-3.4%	149 → 144 nmol/L	neg	improved	✔	✔ improved	#0ca30c	828172	-3.4% ✔
6	hba1c	HbA1c	%	5.3	5.3	0	0	+0.0%	5.3 → 5.3 %	pos	on-target	●	● on-target	#2a78d6	2783446	+0.0% ●
7	glucose	Glucose	mg/dL	96	89	-7	-7.3	-7.3%	96 → 89 mg/dL	neg	improved	✔	✔ improved	#0ca30c	828172	-7.3% ✔
8	hscrp	hs-CRP	mg/L	0.9	0.8	-0.1	-11.1	-11.1%	0.9 → 0.8 mg/L	neg	on-target	●	● on-target	#2a78d6	2783446	-11.1% ●
9	vitamin-d	Vitamin D	ng/mL	52	55	3	5.8	+5.8%	52 → 55 ng/mL	pos	on-target	●	● on-target	#2a78d6	2783446	+5.8% ●
10	tsh	TSH	mIU/L	2.3	2.1	-0.2	-8.7	-8.7%	2.3 → 2.1 mIU/L	neg	on-target	●	● on-target	#2a78d6	2783446	-8.7% ●
11	ferritin	Ferritin	ng/mL	160	154	-6	-3.8	-3.8%	160 → 154 ng/mL	neg	improved	✔	✔ improved	#0ca30c	828172	-3.8% ✔
12	testosterone-total	Testosterone	ng/dL	602	618	16	2.7	+2.7%	602 → 618 ng/dL	pos	on-target	●	● on-target	#2a78d6	2783446	+2.7% ●
13	alt	ALT	U/L	26	24	-2	-7.7	-7.7%	26 → 24 U/L	neg	on-target	●	● on-target	#2a78d6	2783446	-7.7% ●
EOD

array LK = ['improved', 'on-target']
array LL = ['✔ improved', '● on-target']
array LC = ['#0ca30c', '#2a78d6']
array YL = ['LDL-C', 'HDL-C', 'Triglycerides', 'ApoB', 'Lp(a)', 'HbA1c', 'Glucose', 'hs-CRP', 'Vitamin D', 'TSH', 'Ferritin', 'Testosterone', 'ALT']
N = 13
text = ('svg' eq 'text')

set label 1 'Change 2025-03-10 → 2025-09-15 · alex' at screen 0.015, screen 1 offset 0,-1.3 left font 'DejaVu Sans'.' Bold,16' textcolor rgb '#0b0b0b'
set label 2 'percent change per marker; judged toward or away from target' at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb '#52514e'
set tmargin 5.5
set rmargin 4
set border 0
set tics nomirror textcolor rgb '#52514e'
set grid xtics linetype 1 linecolor rgb '#e1e0d9' linewidth 1
set grid noytics
set key outside bottom center horizontal Left reverse noautotitle textcolor rgb '#52514e' samplen 1.2 spacing 1.2 width 1
set style fill solid 1 noborder

# Text: no fills or grid (they turn into noise), the short change label
# only, and one terminal line per bar so no row is overdrawn.
if (text) {
  unset grid; set tmargin 4; set style fill empty border; set border 1
  set terminal dumb noenhanced size 72, (N + 8)
}
label(side) = strcol('side') eq side ? (text ? strcol('pct_label').' '.strcol('glyph') : strcol('text')) : ''
# Bars are filled boxes, or plain strokes from 0 in text.
bars = text ? 'vectors nohead' : 'boxxyerror'
bx(p) = text ? 0 : p / 2
bdx(p) = text ? p : abs(p) / 2
bdy = text ? 0 : 0.31
gap = text ? 2 : 0.8

set xrange [-16:16]
if (text) { set xrange [1.4 * -16:1.4 * 16] }
set yrange [0.4:N + 0.6]
if (text) { set yrange [0.5:N + 0.5] }
# Two or three ticks each side of 0, at a 1-2-5 step.
nice(x) = (e = 10**floor(log10(x)), m = x / e, (m >= 5 ? 5 : m >= 2 ? 2 : 1) * e)
set xtics nice(16 / 2.0) scale 0 format '%g%%'
set ytics scale 0 font ',11' textcolor rgb '#0b0b0b' ()
do for [i=1:N] { set ytics add (YL[i] N + 1 - i) }
set xlabel '% change since the earlier draw' textcolor rgb '#52514e' offset 0,0.3
if (!text) { set bmargin 5 } else { unset xlabel }

set arrow 1 from first 0, graph 0 to first 0, graph 1 nohead front \
    linecolor rgb '#52514e' linewidth 1.5

row(i) = N + 1 - i

plot \
  for [i=1:|LK|] $data \
      using (strcol('verdict') eq LK[i] ? bx(column('pct')) : NaN):(row(column('index'))):(bdx(column('pct'))):(bdy) \
      with @bars linecolor rgb LC[i] linewidth 2 title LL[i], \
  $data using 'pct':(row(column('index'))):(label('pos')) \
      with labels left offset gap,0 font ',10' textcolor rgb '#0b0b0b' notitle, \
  $data using 'pct':(row(column('index'))):(label('neg')) \
      with labels right offset -gap,0 font ',10' textcolor rgb '#0b0b0b' notitle
