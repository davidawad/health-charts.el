# health-chart inrange: per marker, the share of its draws below, inside
# and above the reference range as one 100% stacked bar, segments colored
# by status (glyph and word in the key) with the draw count inside.
# The backend has already chosen the terminal, the output and a
# tab-separated datafile with column headers.

$data << EOD
{{data}}
EOD

array YL = {{y.domain}}
array LK = {{legend.key}}
array LL = {{legend.label}}
array LC = {{legend.color}}
n = |YL|
text = ({{format}} eq 'text')
h = 0.36

set label 1 {{title}} at screen 0.015, screen 1 offset 0,-1.3 left font {{font}}.' Bold,16' textcolor rgb {{colors.ink}}
set label 2 {{subtitle}} at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb {{colors.secondary}}
set tmargin 5.5
set lmargin 17
set rmargin 14
set bmargin 7.5
set border 0
set xrange [0:1]
set yrange [n+0.6:0.4]
set xtics scale 0 nomirror textcolor rgb {{colors.secondary}} offset 0,-0.3
set xtics ()
set xtics add ('0%%' 0, '25%%' 0.25, '50%%' 0.5, '75%%' 0.75, '100%%' 1)
set grid xtics linetype 1 linecolor rgb {{colors.grid}} linewidth 1
set xlabel {{x.title}} textcolor rgb {{colors.secondary}} offset 0,0.3
set ytics scale 0 nomirror textcolor rgb {{colors.ink}} offset -0.5,0
set ytics ()
do for [i=1:n] { set ytics add (YL[i] i) }
set key outside bottom center horizontal Left reverse noautotitle textcolor rgb {{colors.secondary}} samplen 1.5 spacing 1.2 width 1

if (text) {
  unset grid; unset label 2
  set label 1 at screen 0, screen 1 offset 0,-0.5
  set terminal dumb noenhanced size {{text_width}}, n + 8
  set tmargin 2; set bmargin 4; set rmargin 16
  unset xlabel; unset key
  set style fill empty border
}

plot \
  for [i=1:|LK|] $data using (strcol('status') eq LK[i] ? 0.5 * (column('x') + column('x2')) : NaN):'index':'x':'x2':(column('index')-h):(column('index')+h) \
      with boxxyerror fillcolor rgb LC[i] fillstyle solid 1 border rgb {{colors.surface}} linewidth 1.5 title LL[i], \
  $data using (strcol('status') eq 'suboptimal' ? column('mid') : NaN):'index':'seg_label' \
      with labels textcolor rgb {{colors.ink}} font ',10' notitle, \
  $data using (strcol('status') ne 'suboptimal' ? column('mid') : NaN):'index':'seg_label' \
      with labels textcolor rgb '#ffffff' font ',10' notitle,\
  $data using (column('x2') > 0.9999 ? 1 : NaN):'index':'summary' with labels left offset 1.5,0 textcolor rgb {{colors.ink}} notitle
