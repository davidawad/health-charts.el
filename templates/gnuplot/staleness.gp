# health-chart staleness: days since each indicator's draw as horizontal
# bars colored by state (glyph and word in the key and at each bar end),
# with the due and stale thresholds as labeled vertical lines.  The
# backend has already chosen the terminal, the output and a
# tab-separated datafile with column headers.

$data << EOD
{{data}}
EOD

array LK = {{legend.key}}
array LL = {{legend.label}}
array LC = {{legend.color}}
array YL = {{rows.label}}
array TV = {{overlays.thresholds.value}}
array TL = {{overlays.thresholds.label}}
array TK = {{overlays.thresholds.key}}
array TC = {{overlays.thresholds.color}}
N = {{rows|length}}
text = ({{format}} eq 'text')
xmax = {{x.domain.1}}

set label 1 {{title}} at screen 0.015, screen 1 offset 0,-1.3 left font {{font}}.' Bold,16' textcolor rgb {{colors.ink}}
set label 2 {{subtitle}} at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb {{colors.secondary}}
set tmargin 7
set rmargin 4
set bmargin 5
set border 1 linecolor rgb {{colors.axis}}
set tics nomirror textcolor rgb {{colors.secondary}}
set grid xtics linetype 1 linecolor rgb {{colors.grid}} linewidth 1
set grid noytics
set key outside bottom center horizontal Left reverse noautotitle textcolor rgb {{colors.secondary}} samplen 1.2 spacing 1.2 width 1
set style fill solid 1 noborder
set xlabel {{x.title}} textcolor rgb {{colors.secondary}} offset 0,0.3

# Text: no fills or grid (they turn into noise), bars as plain strokes,
# the days and glyph only at the bar end, one terminal line per bar.
if (text) {
  unset grid; unset xlabel; unset bmargin; set tmargin 5; set style fill empty border
  set terminal dumb noenhanced size {{text_width}}, (N + 10)
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
set ytics scale 0 font ',11' textcolor rgb {{colors.ink}} ()
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
      with labels left offset gap,0 font ',10' textcolor rgb {{colors.ink}} notitle
