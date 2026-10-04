# health-chart dual: two related markers over time, one per axis (left
# solid, right dashed; axis titles in the marker's color), points by
# status (shape + color, glyph and word in the key), each marker's upper
# reference limit dotted on its own axis.  The backend has already chosen
# the terminal, the output and a tab-separated datafile with column
# headers.

$data << EOD
{{data}}
EOD

array LK = {{legend.key}}
array LL = {{legend.label}}
array LC = {{legend.color}}
array LP = {{legend.pt}}
array XT = {{x.ticks.sec}}
array XL = {{x.ticks.label}}
array TV = {{overlays.thresholds.value}}
array TA = {{overlays.thresholds.axis}}
array TL = {{overlays.thresholds.label}}
array TC = {{overlays.thresholds.color}}
text = ({{format}} eq 'text')

set label 1 {{title}} at screen 0.015, screen 1 offset 0,-1.3 left font {{font}}.' Bold,16' textcolor rgb {{colors.ink}}
set label 2 {{subtitle}} at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb {{colors.secondary}}
set tmargin 5
set rmargin 9
set lmargin 10
set border 11 linecolor rgb {{colors.axis}}
set tics nomirror textcolor rgb {{colors.secondary}}
set grid ytics linetype 1 linecolor rgb {{colors.grid}} linewidth 1
set grid noxtics
set key outside bottom center horizontal Left reverse noautotitle textcolor rgb {{colors.secondary}} samplen 1.5 spacing 1.2 width 1

if (text) { unset grid; set tmargin 4 }

set xdata time
set timefmt '%Y-%m-%d'
set xrange [{{x.domain.0}}:{{x.domain.1}}]
set xtics ()
do for [i=1:|XT|] { set xtics add (XL[i] XT[i]) }
set yrange [{{layout.left.domain.0}}:{{layout.left.domain.1}}]
set y2range [{{layout.right.domain.0}}:{{layout.right.domain.1}}]
set ytics nomirror textcolor rgb {{layout.left.color}}
set y2tics nomirror textcolor rgb {{layout.right.color}}
set ylabel {{layout.left.title}} textcolor rgb {{layout.left.color}} font {{font}}.' Bold,12'
set y2label {{layout.right.title}} textcolor rgb {{layout.right.color}} font {{font}}.' Bold,12'

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
      linewidth 3 linecolor rgb {{layout.left.color}} notitle, \
  $data using 'date':(strcol('axis') eq 'right' ? column('value') : NaN) axes x1y2 with lines \
      linewidth 3 dashtype 2 linecolor rgb {{layout.right.color}} notitle, \
  for [i=1:|LK|] $data using 'date':(strcol('axis') eq 'left' && strcol('status') eq LK[i] ? column('value') : NaN) \
      axes x1y1 with points pointtype LP[i] pointsize 1.6 linecolor rgb LC[i] title LL[i], \
  for [i=1:|LK|] $data using 'date':(strcol('axis') eq 'right' && strcol('status') eq LK[i] ? column('value') : NaN) \
      axes x1y2 with points pointtype LP[i] pointsize 1.6 linecolor rgb LC[i] notitle
