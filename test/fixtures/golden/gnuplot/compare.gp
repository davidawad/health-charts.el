# health-chart: compare chart, svg, generated from a template
set encoding utf8
set terminal svg size 720,360 dynamic noenhanced font 'DejaVu Sans,12' background '#fcfcfb'
set datafile separator "\t"
set datafile columnheaders
# health-chart compare: one marker over time for several people, a line
# and point shape per person (glyph and name in the key), reference and
# optimal bands shaded, each person's latest value annotated.  The
# backend has already chosen the terminal, the output and a
# tab-separated datafile with column headers.

$data << EOD
person	marker	label	date	value	unit	value_label	status	glyph	status_label	color	rgb	shape	pt	ref_low	ref_high	opt_low	opt_high	series	series_label	series_color	latest
alex	vitamin-d	Vitamin D	2021-11-08	22	ng/mL	22 ng/mL	low	▼	▼ low	#d03b3b	13646651	triangle-down	11	30	100	40	60	alex	● alex	#2a78d6	0
alex	vitamin-d	Vitamin D	2022-05-16	26	ng/mL	26 ng/mL	low	▼	▼ low	#d03b3b	13646651	triangle-down	11	30	100	40	60	alex	● alex	#2a78d6	0
alex	vitamin-d	Vitamin D	2022-11-14	34	ng/mL	34 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	100	40	60	alex	● alex	#2a78d6	0
alex	vitamin-d	Vitamin D	2023-06-05	41	ng/mL	41 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	alex	● alex	#2a78d6	0
alex	vitamin-d	Vitamin D	2024-01-15	38	ng/mL	38 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	100	40	60	alex	● alex	#2a78d6	0
alex	vitamin-d	Vitamin D	2024-08-12	47	ng/mL	47 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	alex	● alex	#2a78d6	0
alex	vitamin-d	Vitamin D	2025-03-10	52	ng/mL	52 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	alex	● alex	#2a78d6	0
alex	vitamin-d	Vitamin D	2025-09-15	55	ng/mL	55 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	alex	● alex	#2a78d6	1
sam	vitamin-d	Vitamin D	2022-01-24	48	ng/mL	48 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	sam	■ sam	#eb6834	0
sam	vitamin-d	Vitamin D	2022-08-01	44	ng/mL	44 ng/mL	optimal	●	● optimal	#0ca30c	828172	circle	7	30	100	40	60	sam	■ sam	#eb6834	0
sam	vitamin-d	Vitamin D	2023-02-13	36	ng/mL	36 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	100	40	60	sam	■ sam	#eb6834	0
sam	vitamin-d	Vitamin D	2023-09-11	31	ng/mL	31 ng/mL	suboptimal	◐	◐ suboptimal	#e09a00	14719488	diamond	13	30	100	40	60	sam	■ sam	#eb6834	0
sam	vitamin-d	Vitamin D	2024-04-08	27	ng/mL	27 ng/mL	low	▼	▼ low	#d03b3b	13646651	triangle-down	11	30	100	40	60	sam	■ sam	#eb6834	0
sam	vitamin-d	Vitamin D	2024-11-18	24	ng/mL	24 ng/mL	low	▼	▼ low	#d03b3b	13646651	triangle-down	11	30	100	40	60	sam	■ sam	#eb6834	0
sam	vitamin-d	Vitamin D	2025-06-23	29	ng/mL	29 ng/mL	low	▼	▼ low	#d03b3b	13646651	triangle-down	11	30	100	40	60	sam	■ sam	#eb6834	1
EOD
$latest << EOD
date	value	text	status_label	color	label_y	series	series_label	series_color
2025-09-15	55	alex 55 ng/mL	● optimal	#0ca30c	59.64	alex	● alex	#2a78d6
2025-06-23	29	sam 29 ng/mL	▼ low	#d03b3b	33.64	sam	■ sam	#eb6834
EOD

array SN = ['alex', 'sam']
array SL = ['● alex', '■ sam']
array SC = ['#2a78d6', '#eb6834']
array SP = [7, 5]
array AC = ['#2a78d6', '#eb6834']
array XT = [1640995200, 1672531200, 1704067200, 1735689600]
array XL = ['2022', '2023', '2024', '2025']
text = ('svg' eq 'text')

set label 1 'Vitamin D · alex vs sam' at screen 0.015, screen 1 offset 0,-1.3 left font 'DejaVu Sans'.' Bold,16' textcolor rgb '#0b0b0b'
set label 2 'latest: alex 55 ng/mL ● optimal · sam 29 ng/mL ▼ low' at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb '#52514e'
set tmargin 6
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
set yrange [18.96:63.04]
set ylabel 'ng/mL' textcolor rgb '#52514e'

if (!text && 30 == 30) {
  set object 1 rect from graph 0, first 30 to graph 1, first 63.04 \
      behind fillcolor rgb '#b8b7ad' fillstyle transparent solid 0.28 noborder
}
if (!text && 40 == 40) {
  set object 2 rect from graph 0, first 40 to graph 1, first 60 \
      behind fillcolor rgb '#0ca30c' fillstyle transparent solid 0.14 noborder
}

# In text mode the bands are left out, so they get no key entry either.
ref_title = text ? '' : 'reference 30–100'
opt_title = text ? '' : 'optimal 40–60'

plot \
  keyentry with boxes \
      fillcolor rgb '#b8b7ad' fillstyle transparent solid 0.28 noborder \
      title ref_title, \
  keyentry with boxes \
      fillcolor rgb '#0ca30c' fillstyle transparent solid 0.14 noborder \
      title opt_title, \
  for [i=1:|SN|] $data using 'date':(strcol('series') eq SN[i] ? column('value') : NaN) \
      with linespoints linewidth 2 pointtype SP[i] pointsize 1.5 linecolor rgb SC[i] title SL[i], \
  for [i=1:|AC|] $latest every ::(i-1)::(i-1) using 'date':'label_y':'text' \
      with labels right offset -0.8,0 font ',12' textcolor rgb AC[i] notitle
