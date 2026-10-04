# health-chart: staleness chart, svg, generated from a template
set encoding utf8
set terminal svg size 720,296 dynamic noenhanced font 'DejaVu Sans,12' background '#fcfcfb'
set datafile separator "\t"
set datafile columnheaders
# health-chart staleness: days since each indicator's draw as horizontal
# bars colored by state (glyph and word in the key and at each bar end),
# with the due and stale thresholds as labeled vertical lines.  The
# backend has already chosen the terminal, the output and a
# tab-separated datafile with column headers.

$data << EOD
index	id	label	date	days	bar	days_label	state	glyph	state_label	color	rgb	marker	person	text
1	health.cardio.apob	ApoB	2025-09-15	16	16	16 d	fresh	●	● fresh	#0ca30c	828172	apob	alex	16 d · ● fresh
2	health.cardio.lp-a	Lp(a)	2025-09-15	16	16	16 d	fresh	●	● fresh	#0ca30c	828172	lpa	alex	16 d · ● fresh
3	health.metabolic.hba1c	HbA1c	2025-09-15	16	16	16 d	fresh	●	● fresh	#0ca30c	828172	hba1c	alex	16 d · ● fresh
4	health.vitamin-d	Vitamin D	2025-09-15	16	16	16 d	fresh	●	● fresh	#0ca30c	828172	vitamin_d	alex	16 d · ● fresh
EOD

array LK = ['fresh']
array LL = ['● fresh']
array LC = ['#0ca30c']
array YL = ['ApoB', 'Lp(a)', 'HbA1c', 'Vitamin D']
array TV = [120, 365]
array TL = ['due after 120 d', 'stale after 365 d']
array TK = ['due', 'stale']
array TC = ['#e09a00', '#d03b3b']
N = 4
text = ('svg' eq 'text')
xmax = 479

set label 1 'Days since draw · sample' at screen 0.015, screen 1 offset 0,-1.3 left font 'DejaVu Sans'.' Bold,16' textcolor rgb '#0b0b0b'
set label 2 'as of 2025-10-01; due after 120 d, stale after 365 d' at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb '#52514e'
set tmargin 7
set rmargin 4
set bmargin 5
set border 1 linecolor rgb '#c3c2b7'
set tics nomirror textcolor rgb '#52514e'
set grid xtics linetype 1 linecolor rgb '#e1e0d9' linewidth 1
set grid noytics
set key outside bottom center horizontal Left reverse noautotitle textcolor rgb '#52514e' samplen 1.2 spacing 1.2 width 1
set style fill solid 1 noborder
set xlabel 'days since draw' textcolor rgb '#52514e' offset 0,0.3

# Text: no fills or grid (they turn into noise), bars as plain strokes,
# the days and glyph only at the bar end, one terminal line per bar.
if (text) {
  unset grid; unset xlabel; unset bmargin; set tmargin 5; set style fill empty border
  set terminal dumb noenhanced size 72, (N + 10)
  xmax = xmax * 1.25
}
bars = text ? 'vectors nohead' : 'boxxyerror'
bx(d) = text ? 0 : d / 2
bdx(d) = text ? d : d / 2
bdy = text ? 0 : 0.31
gap = text ? 1 : 0.8
endlabel(s) = text ? strcol('days_label').' '.strcol('glyph') : strcol('text')

set xrange [0:xmax]
set yrange [0.4:N + 0.6]
if (text) { set yrange [0.5:N + 0.5] }
# About five ticks, at a 1-2-5 step.
nice(x) = (e = 10**floor(log10(x)), m = x / e, (m >= 5 ? 5 : m >= 2 ? 2 : 1) * e)
set xtics nice(xmax / 5.0) scale 0
set ytics scale 0 font ',11' textcolor rgb '#0b0b0b' ()
do for [i=1:N] { set ytics add (YL[i] N + 1 - i) }

do for [i=1:|TV|] {
  set arrow (10 + i) from first TV[i], graph 0 to first TV[i], graph 1 nohead back \
      dashtype (10, 8) linecolor rgb TC[i] linewidth 1.5
  if (text) {
    set label (10 + i) TK[i] at first TV[i], graph 1 offset 1,0.5 left front textcolor rgb TC[i]
  } else {
    set label (10 + i) TL[i] at first TV[i], graph 1 offset 0,0.9 center front font ',11' textcolor rgb TC[i]
  }
}

row(i) = N + 1 - i

plot \
  for [i=1:|LK|] $data \
      using (strcol('state') eq LK[i] ? bx(column('bar')) : NaN):(row(column('index'))):(bdx(column('bar'))):(bdy) \
      with @bars linecolor rgb LC[i] linewidth 2 title LL[i], \
  $data using 'bar':(row(column('index'))):(endlabel(0)) \
      with labels left offset gap,0 font ',10' textcolor rgb '#0b0b0b' notitle
