# health-chart heatmap: markers (rows) by draw dates (columns), each
# cell colored by status with its glyph and value drawn in it (glyph and
# word in the key).  The backend has already chosen the terminal, the
# output and a tab-separated datafile with column headers.

$data << EOD
{{data}}
EOD

array YL = {{y.domain}}
array XL = {{x.labels}}
array LK = {{legend.key}}
array LL = {{legend.label}}
array LC = {{legend.color}}
ny = |YL|
nx = |XL|
text = ({{format}} eq 'text')
w = 0.46
h = 0.44

set label 1 {{title}} at screen 0.015, screen 1 offset 0,-1.3 left font {{font}}.' Bold,16' textcolor rgb {{colors.ink}}
set label 2 {{subtitle}} at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb {{colors.secondary}}
set tmargin 6.5
set lmargin 17
set rmargin 3
set bmargin 3.5
set border 0
set xrange [0.5:nx+0.5]
set yrange [ny+0.5:0.5]
set x2range [0.5:nx+0.5]
unset xtics
set x2tics scale 0 nomirror textcolor rgb {{colors.secondary}} font ',10.5' offset 0,-0.3
set x2tics ()
do for [i=1:nx] { set x2tics add (XL[i] i) }
set ytics scale 0 nomirror textcolor rgb {{colors.ink}} offset -0.5,0
set ytics ()
do for [i=1:ny] { set ytics add (YL[i] i) }
set key outside bottom center horizontal Left reverse noautotitle textcolor rgb {{colors.secondary}} \
    samplen 1.5 spacing 1.2 width 2

if (text) {
  # Dumb terminal: no fills; the glyph and value are the cell.
  unset label 2
  set label 1 at screen 0, screen 1 offset 0,-0.5
  th = {{text_height}}
  if (th < ny + 6) { th = ny + 6; set terminal dumb noenhanced size {{text_width}}, th }
  set tmargin th - ny - 2; set lmargin 22; set rmargin 1; set bmargin 2
  key = ''
  do for [i=1:|LL|] { key = key . LL[i] . '   ' }
  set label 3 key at graph 0, screen 0 offset 0,0.5 left
  unset ytics; unset x2tics; unset key
  do for [i=1:nx] { set label 200+i XL[i][1:3] . "\n" . XL[i][5:] at first i, graph 1 offset 0,2.5 center }
  do for [i=1:ny] { set label 100+i YL[i] at graph 0, first i offset -1,0 right }
  plot $data using 'x_index':'y_index':'cell_label' with labels
} else {
  # The grid, then the key alone in a full-width plot below it so its
  # entries spread across the figure in one row.
  set multiplot
  unset key
  plot \
    for [i=1:|LK|] $data using 'x_index':(strcol('status') eq LK[i] ? column('y_index') : NaN) \
        :(column('x_index')-w):(column('x_index')+w):(column('y_index')-h):(column('y_index')+h) \
        with boxxyerror fillcolor rgb LC[i] fillstyle solid 0.9 noborder, \
    $data using 'x_index':'y_index':'cell_label' with labels font ',11.5' textcolor rgb {{colors.surface}}
  unset label; unset ytics; unset x2tics
  set lmargin at screen 0.03; set rmargin at screen 0.97
  set tmargin at screen 0.07; set bmargin at screen 0.005
  set yrange [0:1]
  set key inside center center horizontal Left reverse noautotitle textcolor rgb {{colors.secondary}} \
      samplen 1.5 spacing 1.2 width 2
  plot 2 with lines linecolor rgb {{colors.surface}} notitle, \
    for [i=1:|LK|] keyentry with boxes fillcolor rgb LC[i] fillstyle solid 0.9 noborder title LL[i]
  unset multiplot
}
