# health-chart: bullet chart, svg, generated from a template
set encoding utf8
set terminal svg size 720,572 dynamic noenhanced font 'DejaVu Sans,12' background '#fcfcfb'
set datafile separator "\t"
set datafile columnheaders
# health-chart bullet: one row per marker on its own normalized 0..1
# track, reference and optimal ranges as bands, the latest value marked
# by status (shape + color; glyph and word in the label beside it).
# The backend has already chosen the terminal, the output and a
# tab-separated datafile with column headers.

$data << EOD
person	marker	label	date	value	unit	value_label	status	glyph	status_label	color	rgb	shape	pt	ref_low	ref_high	opt_low	opt_high	index	domain_lo	domain_hi	pos	ref_x	ref_x2	opt_x	opt_x2	ref_range	opt_range	latest_label
alex	ldl-c	LDL-C	2025-09-15	76	mg/dL	76 mg/dL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	0	100	NaN	70	1	0	112	0.6786	0	0.8929	0	0.625	0–100	≤70	76 mg/dL  ◐ suboptimal
alex	hdl-c	HDL-C	2025-09-15	61	mg/dL	61 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	40	NaN	60	NaN	2	37.48	63.52	0.9032	0.0968	1	0.8648	1	≥40	≥60	61 mg/dL  ● optimal
alex	triglycerides	Triglycerides	2025-09-15	88	mg/dL	88 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	0	150	NaN	100	3	0	168	0.5238	0	0.8929	0	0.5952	0–150	≤100	88 mg/dL  ● optimal
alex	apob	ApoB	2025-09-15	72	mg/dL	72 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	0	90	NaN	80	4	0	100.8	0.7143	0	0.8929	0	0.7937	0–90	≤80	72 mg/dL  ● optimal
alex	lpa	Lp(a)	2025-09-15	144	nmol/L	144 nmol/L	high	▲	▲ high	#d03b3b	13646651	triangle-up	9	0	75	NaN	30	5	0	161.28	0.8929	0	0.465	0	0.186	0–75	≤30	144 nmol/L  ▲ high
alex	hba1c	HbA1c	2025-09-15	5.3	%	5.3 %	optimal	●	● optimal	#0ca30c	828172	circle	7	4.0	5.6	NaN	5.3	6	3.808	5.792	0.752	0.0968	0.9032	0	0.752	4–5.6	≤5.3	5.3 %  ● optimal
alex	glucose	Glucose	2025-09-15	89	mg/dL	89 mg/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	70	99	72	90	7	66.52	102.48	0.6251	0.0968	0.9032	0.1524	0.6529	70–99	72–90	89 mg/dL  ● optimal
alex	hscrp	hs-CRP	2025-09-15	0.8	mg/L	0.8 mg/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0	3.0	NaN	1.0	8	0	3.36	0.2381	0	0.8929	0	0.2976	0–3	≤1	0.8 mg/L  ● optimal
alex	vitamin-d	Vitamin D	2025-09-15	55	ng/mL	55 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	9	21.6	108.4	0.3848	0.0968	0.9032	0.212	0.4424	30–100	40–60	55 ng/mL  ● optimal
alex	tsh	TSH	2025-09-15	2.1	mIU/L	2.1 mIU/L	optimal	●	● optimal	#0ca30c	828172	circle	7	0.4	4.0	0.5	2.5	10	0	4.432	0.4738	0.0903	0.9025	0.1128	0.5641	0.4–4	0.5–2.5	2.1 mIU/L  ● optimal
alex	ferritin	Ferritin	2025-09-15	154	ng/mL	154 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	400	50	150	11	0	444.4	0.3465	0.0675	0.9001	0.1125	0.3375	30–400	50–150	154 ng/mL  ◐ suboptimal
alex	testosterone-total	Testosterone	2025-09-15	618	ng/dL	618 ng/dL	optimal	●	● optimal	#0ca30c	828172	circle	7	264	916	500	900	12	185.76	994.24	0.5346	0.0968	0.9032	0.3887	0.8834	264–916	500–900	618 ng/dL  ● optimal
alex	alt	ALT	2025-09-15	24	U/L	24 U/L	optimal	●	● optimal	#0ca30c	828172	circle	7	7	56	NaN	30	13	1.12	61.88	0.3766	0.0968	0.9032	0	0.4753	7–56	≤30	24 U/L  ● optimal
EOD

array YL = ['LDL-C', 'HDL-C', 'Triglycerides', 'ApoB', 'Lp(a)', 'HbA1c', 'Glucose', 'hs-CRP', 'Vitamin D', 'TSH', 'Ferritin', 'Testosterone', 'ALT']
array RL = ['76 mg/dL  ◐ suboptimal', '61 mg/dL  ● optimal', '88 mg/dL  ● optimal', '72 mg/dL  ● optimal', '144 nmol/L  ▲ high', '5.3 %  ● optimal', '89 mg/dL  ● optimal', '0.8 mg/L  ● optimal', '55 ng/mL  ● optimal', '2.1 mIU/L  ● optimal', '154 ng/mL  ◐ suboptimal', '618 ng/dL  ● optimal', '24 U/L  ● optimal']
array LK = ['optimal', 'suboptimal', 'high']
array LL = ['● optimal', '◐ suboptimal', '▲ high']
array LC = ['#0ca30c', '#e09a00', '#d03b3b']
array LP = [7, 13, 9]
n = 13
text = ('svg' eq 'text')
h = 0.31

set label 1 'Latest vs range · alex' at screen 0.015, screen 1 offset 0,-1.3 left font 'DejaVu Sans'.' Bold,16' textcolor rgb '#0b0b0b'
set label 2 'latest draw per marker, each on its own scale; shaded: reference and optimal ranges' at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb '#52514e'
set tmargin 6
set lmargin 17
set rmargin 27
set border 0
unset xtics
set ytics scale 0 nomirror textcolor rgb '#0b0b0b' offset -0.5,0
set ytics ()
do for [i=1:|YL|] { set ytics add (YL[i] i) }
set xrange [0:1]
set yrange [n+0.7:0.3]
set bmargin 4
set key outside bottom center horizontal Left reverse noautotitle textcolor rgb '#52514e' samplen 1.5 spacing 1.2 width 1

do for [i=1:|RL|] {
  set label 10+i RL[i] at graph 1, first i offset 1.5,0 left textcolor rgb '#0b0b0b'
}

if (text) {
  # Dumb terminal: |-----| is the reference range, ===== the optimal
  # range, the status glyph the latest value; labels carry the words.
  if (20 < n + 5) { set terminal dumb noenhanced size 72, n + 5 }
  unset label 2
  set label 1 at screen 0, screen 1 offset 0,-0.5
  set tmargin 1; set bmargin 2; set lmargin 22; set rmargin 26
  set label 3 '|---| ' . 'reference range' . '   ==== ' . 'optimal range' \
      at graph 0, screen 0 offset 0,0.5 left
  set yrange [n+0.5:0.5]
  unset ytics
  do for [i=1:|YL|] { set label 100+i YL[i] at graph 0, first i offset -1,0 right }
  do for [i=1:|RL|] { set label 10+i offset 2,0 }
  m = 2 * 72
  unset key
  plot \
    $data using 'ref_x':'index':(column('ref_x2') - column('ref_x')):(0) with vectors nohead, \
    $data using 'ref_x':'index':('|') with labels, \
    $data using 'ref_x2':'index':('|') with labels, \
    for [k=0:m] $data using (x = real(k) / m, x >= column('opt_x') && x <= column('opt_x2') ? x : NaN):'index' \
        with points pointtype '=', \
    $data using 'pos':'index':'glyph' with labels textcolor rgb '#0b0b0b'
} else {
  # The chart, then the key alone in a full-width plot below it so its
  # entries can spread across the figure.
  set multiplot
  unset key
  plot \
    $data using (0.5):'index':(0):(1):(column('index')-h):(column('index')+h) with boxxyerror \
        fillcolor rgb '#e1e0d9' fillstyle transparent solid 0.55 noborder, \
    $data using (0.5):'index':'ref_x':'ref_x2':(column('index')-h):(column('index')+h) with boxxyerror \
        fillcolor rgb '#b8b7ad' fillstyle transparent solid 0.28 noborder, \
    $data using (0.5):'index':'opt_x':'opt_x2':(column('index')-h):(column('index')+h) with boxxyerror \
        fillcolor rgb '#0ca30c' fillstyle transparent solid 0.14 noborder, \
    $data using 'pos':(column('index')-0.4):(0):(0.8):'rgb' with vectors nohead linewidth 2.5 \
        linecolor rgb variable, \
    for [i=1:|LK|] $data using (strcol('status') eq LK[i] ? column('pos') : NaN):'index' \
        with points pointtype LP[i] pointsize 1.7 linecolor rgb LC[i]
  unset label; unset ytics
  set lmargin at screen 0.03; set rmargin at screen 0.97
  set tmargin at screen 0.1; set bmargin at screen 0.01
  set key inside center center horizontal Left reverse noautotitle textcolor rgb '#52514e' \
      samplen 1.5 spacing 1.2 width 2
  set yrange [0:1]
  plot \
    2 with lines linecolor rgb '#fcfcfb' notitle, \
    keyentry with boxes fillcolor rgb '#b8b7ad' \
        fillstyle transparent solid 0.28 noborder title 'reference range', \
    keyentry with boxes fillcolor rgb '#0ca30c' \
        fillstyle transparent solid 0.14 noborder title 'optimal range', \
    for [i=1:|LK|] keyentry with points pointtype LP[i] pointsize 1.7 linecolor rgb LC[i] title LL[i]
  unset multiplot
}
