# health-chart delta: percent change per marker between two draws,
# diverging bars from 0 colored by verdict (glyph and word in the key),
# each bar labeled with its change and its before and after values.
# The backend has already chosen the terminal, the output and a
# tab-separated datafile with column headers.

$data << EOD
{{data}}
EOD

array LK = {{legend.key}}
array LL = {{legend.label}}
array LC = {{legend.color}}
array YL = {{rows.label}}
N = {{rows|length}}
text = ({{format}} eq 'text')

set label 1 {{title}} at screen 0.015, screen 1 offset 0,-1.3 left font {{font}}.' Bold,16' textcolor rgb {{colors.ink}}
set label 2 {{subtitle}} at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb {{colors.secondary}}
set tmargin 5.5
set rmargin 4
set border 0
set tics nomirror textcolor rgb {{colors.secondary}}
set grid xtics linetype 1 linecolor rgb {{colors.grid}} linewidth 1
set grid noytics
set key outside bottom center horizontal Left reverse noautotitle textcolor rgb {{colors.secondary}} samplen 1.2 spacing 1.2 width 1
set style fill solid 1 noborder

# Text: no fills or grid (they turn into noise), the short change label
# only, and one terminal line per bar so no row is overdrawn.
if (text) {
  unset grid; set tmargin 4; set style fill empty border; set border 1
  set terminal dumb noenhanced size {{text_width}}, (N + 8)
}
label(side) = strcol('side') eq side ? (text ? strcol('pct_label').' '.strcol('glyph') : strcol('text')) : ''
# Bars are filled boxes, or plain strokes from 0 in text.
bars = text ? 'vectors nohead' : 'boxxyerror'
bx(p) = text ? 0 : p / 2
bdx(p) = text ? p : abs(p) / 2
bdy = text ? 0 : 0.31
gap = text ? 2 : 0.8

set xrange [{{x.domain.0}}:{{x.domain.1}}]
if (text) { set xrange [1.4 * {{x.domain.0}}:1.4 * {{x.domain.1}}] }
set yrange [0.4:N + 0.6]
if (text) { set yrange [0.5:N + 0.5] }
# Two or three ticks each side of 0, at a 1-2-5 step.
nice(x) = (e = 10**floor(log10(x)), m = x / e, (m >= 5 ? 5 : m >= 2 ? 2 : 1) * e)
set xtics nice({{x.domain.1}} / 2.0) scale 0 format '%g%%'
set ytics scale 0 font ',11' textcolor rgb {{colors.ink}} ()
do for [i=1:N] { set ytics add (YL[i] N + 1 - i) }
set xlabel {{x.title}} textcolor rgb {{colors.secondary}} offset 0,0.3
if (!text) { set bmargin 5 } else { unset xlabel }

set arrow 1 from first 0, graph 0 to first 0, graph 1 nohead front \
    linecolor rgb {{colors.secondary}} linewidth 1.5

row(i) = N + 1 - i

plot \
  for [i=1:|LK|] $data \
      using (strcol('verdict') eq LK[i] ? bx(column('pct')) : NaN):(row(column('index'))):(bdx(column('pct'))):(bdy) \
      with @bars linecolor rgb LC[i] linewidth 2 title LL[i], \
  $data using 'pct':(row(column('index'))):(label('pos')) \
      with labels left offset gap,0 font ',10' textcolor rgb {{colors.ink}} notitle, \
  $data using 'pct':(row(column('index'))):(label('neg')) \
      with labels right offset -gap,0 font ',10' textcolor rgb {{colors.ink}} notitle
