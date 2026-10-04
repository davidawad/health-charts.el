# health-chart: dumbbell chart, svg, generated from a template
set encoding utf8
set terminal svg size 720,582 dynamic noenhanced font 'DejaVu Sans,12' background '#fcfcfb'
set datafile separator "\t"
set datafile columnheaders
# health-chart dumbbell: per marker, the first draw (hollow) to the latest
# (filled, colored by verdict; glyph and word in the label and key) on
# the marker's own range scale (0 = reference low, 1 = reference high).
# The backend has already chosen the terminal, the output and a
# tab-separated datafile with column headers.

$data << EOD
person	marker	label	date	value	unit	value_label	status	glyph	status_label	color	rgb	shape	pt	ref_low	ref_high	opt_low	opt_high	index	before	after	date_before	date_after	norm_before	norm_after	x_before	x_after	verdict	verdict_glyph	verdict_label	verdict_color	verdict_rgb	values_label	span_label	text	ref_x	ref_x2	opt_x	opt_x2	ref_range	opt_range
alex	ldl-c	LDL-C	2025-09-15	76	mg/dL	76 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	100	NaN	70	1	162	76	2021-11-08	2025-09-15	1.62	0.76	1.62	0.76	improved	✔	✔ improved	#0ca30c	828172	162 → 76 mg/dL	Nov 2021 → Sep 2025	✔ improved  162 → 76	0	1	-0.25	0.7	0–100	≤70
alex	hdl-c	HDL-C	2025-09-15	61	mg/dL	61 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	40	NaN	60	NaN	2	38	61	2021-11-08	2025-09-15	-0.05	0.525	-0.05	0.525	improved	✔	✔ improved	#0ca30c	828172	38 → 61 mg/dL	Nov 2021 → Sep 2025	✔ improved  38 → 61	0	1	0.5	2	≥40	≥60
alex	triglycerides	Triglycerides	2025-09-15	88	mg/dL	88 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	0	150	NaN	100	3	212	88	2021-11-08	2025-09-15	1.4133	0.5867	1.4133	0.5867	improved	✔	✔ improved	#0ca30c	828172	212 → 88 mg/dL	Nov 2021 → Sep 2025	✔ improved  212 → 88	0	1	-0.25	0.6667	0–150	≤100
alex	apob	ApoB	2025-09-15	72	mg/dL	72 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	0	90	NaN	80	4	128	72	2021-11-08	2025-09-15	1.4222	0.8	1.4222	0.8	improved	✔	✔ improved	#0ca30c	828172	128 → 72 mg/dL	Nov 2021 → Sep 2025	✔ improved  128 → 72	0	1	-0.25	0.8889	0–90	≤80
alex	lpa	Lp(a)	2025-09-15	144	nmol/L	144 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	5	142	144	2021-11-08	2025-09-15	1.8933	1.92	1.8933	1.92	worsened	✖	✖ worsened	#d03b3b	13646651	142 → 144 nmol/L	Nov 2021 → Sep 2025	✖ worsened  142 → 144	0	1	-0.25	0.4	0–75	≤30
alex	hba1c	HbA1c	2025-09-15	5.3	%	5.3 %	optimal	●	● optimal	#0ca30c	828172	circle	7	4.0	5.6	NaN	5.3	6	5.9	5.3	2021-11-08	2025-09-15	1.1875	0.8125	1.1875	0.8125	improved	✔	✔ improved	#0ca30c	828172	5.9 → 5.3 %	Nov 2021 → Sep 2025	✔ improved  5.9 → 5.3	0	1	-0.25	0.8125	4–5.6	≤5.3
alex	glucose	Glucose	2025-09-15	89	mg/dL	89 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	70	99	72	90	7	108	89	2021-11-08	2025-09-15	1.3103	0.6552	1.3103	0.6552	improved	✔	✔ improved	#0ca30c	828172	108 → 89 mg/dL	Nov 2021 → Sep 2025	✔ improved  108 → 89	0	1	0.069	0.6897	70–99	72–90
alex	hscrp	hs-CRP	2025-09-15	0.8	mg/L	0.8 mg/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0	3.0	NaN	1.0	8	4.2	0.8	2021-11-08	2025-09-15	1.4	0.2667	1.4	0.2667	improved	✔	✔ improved	#0ca30c	828172	4.2 → 0.8 mg/L	Nov 2021 → Sep 2025	✔ improved  4.2 → 0.8	0	1	-0.25	0.3333	0–3	≤1
alex	vitamin-d	Vitamin D	2025-09-15	55	ng/mL	55 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	9	22	55	2021-11-08	2025-09-15	-0.1143	0.3571	-0.1143	0.3571	improved	✔	✔ improved	#0ca30c	828172	22 → 55 ng/mL	Nov 2021 → Sep 2025	✔ improved  22 → 55	0	1	0.1429	0.4286	30–100	40–60
alex	tsh	TSH	2025-09-15	2.1	mIU/L	2.1 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	10	1.8	2.1	2021-11-08	2025-09-15	0.3889	0.4722	0.3889	0.4722	on-target	●	● on-target	#2a78d6	2783446	1.8 → 2.1 mIU/L	Nov 2021 → Sep 2025	● on-target  1.8 → 2.1	0	1	0.0278	0.5833	0.4–4	0.5–2.5
alex	ferritin	Ferritin	2025-09-15	154	ng/mL	154 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	11	182	154	2021-11-08	2025-09-15	0.4108	0.3351	0.4108	0.3351	improved	✔	✔ improved	#0ca30c	828172	182 → 154 ng/mL	Nov 2021 → Sep 2025	✔ improved  182 → 154	0	1	0.0541	0.3243	30–400	50–150
alex	testosterone-total	Testosterone	2025-09-15	618	ng/dL	618 ng/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	264	916	500	900	12	412	618	2021-11-08	2025-09-15	0.227	0.5429	0.227	0.5429	improved	✔	✔ improved	#0ca30c	828172	412 → 618 ng/dL	Nov 2021 → Sep 2025	✔ improved  412 → 618	0	1	0.362	0.9755	264–916	500–900
alex	alt	ALT	2025-09-15	24	U/L	24 U/L	optimal	●	● optimal	#0ca30c	828172	circle	7	7	56	NaN	30	13	48	24	2021-11-08	2025-09-15	0.8367	0.3469	0.8367	0.3469	improved	✔	✔ improved	#0ca30c	828172	48 → 24 U/L	Nov 2021 → Sep 2025	✔ improved  48 → 24	0	1	-0.25	0.4694	7–56	≤30
EOD

array YL = ['LDL-C', 'HDL-C', 'Triglycerides', 'ApoB', 'Lp(a)', 'HbA1c', 'Glucose', 'hs-CRP', 'Vitamin D', 'TSH', 'Ferritin', 'Testosterone', 'ALT']
array LK = ['improved', 'on-target', 'worsened']
array LL = ['✔ improved', '● on-target', '✖ worsened']
array LC = ['#0ca30c', '#2a78d6', '#d03b3b']
n = |YL|
text = ('svg' eq 'text')
h = 0.31
x1 = 2.0

set label 1 'First vs latest draw · alex' at screen 0.015, screen 1 offset 0,-1.3 left font 'DejaVu Sans'.' Bold,16' textcolor rgb '#0b0b0b'
set label 2 'hollow: first draw; filled: latest, colored by verdict; 2021-11-08 to 2025-09-15' at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb '#52514e'
set tmargin 6
set lmargin 17
set rmargin 27
set border 0
set xrange [-0.25:2.0]
set yrange [n+0.7:0.3]
set xtics scale 0 nomirror textcolor rgb '#52514e' offset 0,-0.3
set xtics ()
set xtics add ('reference low' 0, 'reference high' 1)
set xlabel 'position in reference range' textcolor rgb '#52514e' offset 0,0.3
set ytics scale 0 nomirror textcolor rgb '#0b0b0b' offset -0.5,0
set ytics ()
do for [i=1:n] { set ytics add (YL[i] i) }
set bmargin 9
set key outside bottom center horizontal Left reverse noautotitle textcolor rgb '#52514e' samplen 1.5 spacing 1.2 width 1

if (text) {
  unset label 2
  set label 1 at screen 0, screen 1 offset 0,-0.5
  set terminal dumb noenhanced size 72, n + 8
  set tmargin 2; set bmargin 4; set lmargin 17; set rmargin 30
  unset xlabel
  unset key
}

if (!text) {
  set multiplot
  unset key
}
plot \
  $data using (column('ref_x') == column('ref_x') ? 0.5 : NaN):'index':'ref_x':'ref_x2':(column('index')-h):(column('index')+h) \
      with boxxyerror fillcolor rgb '#b8b7ad' fillstyle transparent solid 0.28 noborder, \
  $data using (column('opt_x') == column('opt_x') ? 0.5 : NaN):'index':'opt_x':'opt_x2':(column('index')-h):(column('index')+h) \
      with boxxyerror fillcolor rgb '#0ca30c' fillstyle transparent solid 0.14 noborder, \
  $data using 'x_before':'index':(column('x_after') - column('x_before')):(0):'verdict_rgb' \
      with vectors nohead linewidth 3 linecolor rgb variable, \
  $data using 'x_before':'index' with points pointtype 7 pointsize 1.5 linecolor rgb '#fcfcfb', \
  $data using 'x_before':'index' with points pointtype 6 pointsize 1.5 linewidth 2 linecolor rgb '#52514e', \
  for [i=1:|LK|] $data using (strcol('verdict_label') eq LL[i] ? column('x_after') : NaN):'index' \
      with points pointtype 7 pointsize 1.9 linecolor rgb LC[i], \
  $data using (x1):'index':'text' with labels left offset 1.5,0 textcolor rgb '#0b0b0b'
if (!text) {
  unset label; unset ytics; unset xtics; unset xlabel
  set lmargin at screen 0.03; set rmargin at screen 0.97
  set tmargin at screen 0.1; set bmargin at screen 0.01
  set key inside center center horizontal Left reverse noautotitle textcolor rgb '#52514e' \
      samplen 1.5 spacing 1.2 width 2
  set xrange [0:1]; set yrange [0:1]
  plot \
    2 with lines linecolor rgb '#fcfcfb' notitle, \
    keyentry with boxes fillcolor rgb '#b8b7ad' \
        fillstyle transparent solid 0.28 noborder title 'reference range', \
    keyentry with boxes fillcolor rgb '#0ca30c' \
        fillstyle transparent solid 0.14 noborder title 'optimal range', \
    keyentry with points pointtype 6 pointsize 1.5 linewidth 2 linecolor rgb '#52514e' title 'first draw', \
    for [i=1:|LK|] keyentry with boxes fillcolor rgb LC[i] fillstyle solid noborder title LL[i]
  unset multiplot
}
