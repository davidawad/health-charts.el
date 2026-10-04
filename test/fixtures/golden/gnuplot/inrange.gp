# health-chart: inrange chart, svg, generated from a template
set encoding utf8
set terminal svg size 720,572 dynamic noenhanced font 'DejaVu Sans,12' background '#fcfcfb'
set datafile separator "\t"
set datafile columnheaders
# health-chart inrange: per marker, the share of its draws below, inside
# and above the reference range as one 100% stacked bar, segments colored
# by status (glyph and word in the key) with the draw count inside.
# The backend has already chosen the terminal, the output and a
# tab-separated datafile with column headers.

$data << EOD
index	marker	label	unit	status	glyph	status_label	color	rgb	count	draws	x	x2	mid	seg_label	summary	detail
1	lpa	Lp(a)	nmol/L	high	▲	▲ high	#d03b3b	13646651	8	8	0	1	0.5	▲ 8	0/8 in range	8 of 8 draws high
2	ldl-c	LDL-C	mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	3	8	0	0.375	0.1875	◐ 3	3/8 in range	3 of 8 draws suboptimal
2	ldl-c	LDL-C	mg/dL	high	▲	▲ high	#d03b3b	13646651	5	8	0.375	1	0.6875	▲ 5	3/8 in range	5 of 8 draws high
3	apob	ApoB	mg/dL	optimal	●	● optimal	#0ca30c	828172	2	8	0	0.25	0.125	● 2	4/8 in range	2 of 8 draws optimal
3	apob	ApoB	mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	2	8	0.25	0.5	0.375	◐ 2	4/8 in range	2 of 8 draws suboptimal
3	apob	ApoB	mg/dL	high	▲	▲ high	#d03b3b	13646651	4	8	0.5	1	0.75	▲ 4	4/8 in range	4 of 8 draws high
4	triglycerides	Triglycerides	mg/dL	optimal	●	● optimal	#0ca30c	828172	2	8	0	0.25	0.125	● 2	5/8 in range	2 of 8 draws optimal
4	triglycerides	Triglycerides	mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	3	8	0.25	0.625	0.4375	◐ 3	5/8 in range	3 of 8 draws suboptimal
4	triglycerides	Triglycerides	mg/dL	high	▲	▲ high	#d03b3b	13646651	3	8	0.625	1	0.8125	▲ 3	5/8 in range	3 of 8 draws high
5	hba1c	HbA1c	%	optimal	●	● optimal	#0ca30c	828172	2	8	0	0.25	0.125	● 2	5/8 in range	2 of 8 draws optimal
5	hba1c	HbA1c	%	suboptimal	◐	◐ suboptimal	#e09a00	14719488	3	8	0.25	0.625	0.4375	◐ 3	5/8 in range	3 of 8 draws suboptimal
5	hba1c	HbA1c	%	high	▲	▲ high	#d03b3b	13646651	3	8	0.625	1	0.8125	▲ 3	5/8 in range	3 of 8 draws high
6	glucose	Glucose	mg/dL	optimal	●	● optimal	#0ca30c	828172	1	8	0	0.125	0.0625	● 1	5/8 in range	1 of 8 draws optimal
6	glucose	Glucose	mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	4	8	0.125	0.625	0.375	◐ 4	5/8 in range	4 of 8 draws suboptimal
6	glucose	Glucose	mg/dL	high	▲	▲ high	#d03b3b	13646651	3	8	0.625	1	0.8125	▲ 3	5/8 in range	3 of 8 draws high
7	hscrp	hs-CRP	mg/L	optimal	●	● optimal	#0ca30c	828172	2	8	0	0.25	0.125	● 2	6/8 in range	2 of 8 draws optimal
7	hscrp	hs-CRP	mg/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	4	8	0.25	0.75	0.5	◐ 4	6/8 in range	4 of 8 draws suboptimal
7	hscrp	hs-CRP	mg/L	high	▲	▲ high	#d03b3b	13646651	2	8	0.75	1	0.875	▲ 2	6/8 in range	2 of 8 draws high
8	vitamin-d	Vitamin D	ng/mL	low	▼	▼ low	#d03b3b	13646651	2	8	0	0.25	0.125	▼ 2	6/8 in range	2 of 8 draws low
8	vitamin-d	Vitamin D	ng/mL	optimal	●	● optimal	#0ca30c	828172	4	8	0.25	0.75	0.5	● 4	6/8 in range	4 of 8 draws optimal
8	vitamin-d	Vitamin D	ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	2	8	0.75	1	0.875	◐ 2	6/8 in range	2 of 8 draws suboptimal
9	hdl-c	HDL-C	mg/dL	low	▼	▼ low	#d03b3b	13646651	1	8	0	0.125	0.0625	▼ 1	7/8 in range	1 of 8 draws low
9	hdl-c	HDL-C	mg/dL	optimal	●	● optimal	#0ca30c	828172	1	8	0.125	0.25	0.1875	● 1	7/8 in range	1 of 8 draws optimal
9	hdl-c	HDL-C	mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	6	8	0.25	1	0.625	◐ 6	7/8 in range	6 of 8 draws suboptimal
10	alt	ALT	U/L	optimal	●	● optimal	#0ca30c	828172	3	8	0	0.375	0.1875	● 3	7/8 in range	3 of 8 draws optimal
10	alt	ALT	U/L	suboptimal	◐	◐ suboptimal	#e09a00	14719488	4	8	0.375	0.875	0.625	◐ 4	7/8 in range	4 of 8 draws suboptimal
10	alt	ALT	U/L	high	▲	▲ high	#d03b3b	13646651	1	8	0.875	1	0.9375	▲ 1	7/8 in range	1 of 8 draws high
11	tsh	TSH	mIU/L	optimal	●	● optimal	#0ca30c	828172	8	8	0	1	0.5	● 8	8/8 in range	8 of 8 draws optimal
12	ferritin	Ferritin	ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	8	8	0	1	0.5	◐ 8	8/8 in range	8 of 8 draws suboptimal
13	testosterone-total	Testosterone	ng/dL	optimal	●	● optimal	#0ca30c	828172	5	8	0	0.625	0.3125	● 5	8/8 in range	5 of 8 draws optimal
13	testosterone-total	Testosterone	ng/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	3	8	0.625	1	0.8125	◐ 3	8/8 in range	3 of 8 draws suboptimal
EOD

array YL = ['Lp(a)', 'LDL-C', 'ApoB', 'Triglycerides', 'HbA1c', 'Glucose', 'hs-CRP', 'Vitamin D', 'HDL-C', 'ALT', 'TSH', 'Ferritin', 'Testosterone']
array LK = ['optimal', 'suboptimal', 'low', 'high']
array LL = ['● optimal', '◐ suboptimal', '▼ low', '▲ high']
array LC = ['#0ca30c', '#e09a00', '#d03b3b', '#d03b3b']
n = |YL|
text = ('svg' eq 'text')
h = 0.36

set label 1 'Draws by status · alex' at screen 0.015, screen 1 offset 0,-1.3 left font 'DejaVu Sans'.' Bold,16' textcolor rgb '#0b0b0b'
set label 2 'share of each marker''s draws below, inside and above its reference range; worst first' at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb '#52514e'
set tmargin 5.5
set lmargin 17
set rmargin 14
set bmargin 7.5
set border 0
set xrange [0:1]
set yrange [n+0.6:0.4]
set xtics scale 0 nomirror textcolor rgb '#52514e' offset 0,-0.3
set xtics ()
set xtics add ('0%%' 0, '25%%' 0.25, '50%%' 0.5, '75%%' 0.75, '100%%' 1)
set grid xtics linetype 1 linecolor rgb '#e1e0d9' linewidth 1
set xlabel 'share of draws' textcolor rgb '#52514e' offset 0,0.3
set ytics scale 0 nomirror textcolor rgb '#0b0b0b' offset -0.5,0
set ytics ()
do for [i=1:n] { set ytics add (YL[i] i) }
set key outside bottom center horizontal Left reverse noautotitle textcolor rgb '#52514e' samplen 1.5 spacing 1.2 width 1

if (text) {
  unset grid; unset label 2
  set label 1 at screen 0, screen 1 offset 0,-0.5
  set terminal dumb noenhanced size 72, n + 8
  set tmargin 2; set bmargin 4; set rmargin 16
  unset xlabel; unset key
  set style fill empty border
}

plot \
  for [i=1:|LK|] $data using (strcol('status') eq LK[i] ? 0.5 * (column('x') + column('x2')) : NaN):'index':'x':'x2':(column('index')-h):(column('index')+h) \
      with boxxyerror fillcolor rgb LC[i] fillstyle solid 1 border rgb '#fcfcfb' linewidth 1.5 title LL[i], \
  $data using (strcol('status') eq 'suboptimal' ? column('mid') : NaN):'index':'seg_label' \
      with labels textcolor rgb '#0b0b0b' font ',10' notitle, \
  $data using (strcol('status') ne 'suboptimal' ? column('mid') : NaN):'index':'seg_label' \
      with labels textcolor rgb '#ffffff' font ',10' notitle,\
  $data using (column('x2') > 0.9999 ? 1 : NaN):'index':'summary' with labels left offset 1.5,0 textcolor rgb '#0b0b0b' notitle
