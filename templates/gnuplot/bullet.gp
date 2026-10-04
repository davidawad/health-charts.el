# health-chart bullet: one row per marker on its own normalized 0..1
# track, reference and optimal ranges as bands, the latest value marked
# by status (shape + color; glyph and word in the label beside it).
# The backend has already chosen the terminal, the output and a
# tab-separated datafile with column headers.

$data << EOD
{{data}}
EOD

array YL = {{y.domain}}
array RL = {{data.latest_label}}
array LK = {{legend.key}}
array LL = {{legend.label}}
array LC = {{legend.color}}
array LP = {{legend.pt}}
n = {{data|length}}
text = ({{format}} eq 'text')
h = 0.31

set label 1 {{title}} at screen 0.015, screen 1 offset 0,-1.3 left font {{font}}.' Bold,16' textcolor rgb {{colors.ink}}
set label 2 {{subtitle}} at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb {{colors.secondary}}
set tmargin 6
set lmargin 17
set rmargin 27
set border 0
unset xtics
set ytics scale 0 nomirror textcolor rgb {{colors.ink}} offset -0.5,0
set ytics ()
do for [i=1:|YL|] { set ytics add (YL[i] i) }
set xrange [0:1]
set yrange [n+0.7:0.3]
set bmargin 4
set key outside bottom center horizontal Left reverse noautotitle textcolor rgb {{colors.secondary}} samplen 1.5 spacing 1.2 width 1

do for [i=1:|RL|] {
  set label 10+i RL[i] at graph 1, first i offset 1.5,0 left textcolor rgb {{colors.ink}}
}

if (text) {
  # Dumb terminal: |-----| is the reference range, ===== the optimal
  # range, the status glyph the latest value; labels carry the words.
  if ({{text_height}} < n + 5) { set terminal dumb noenhanced size {{text_width}}, n + 5 }
  unset label 2
  set label 1 at screen 0, screen 1 offset 0,-0.5
  set tmargin 1; set bmargin 2; set lmargin 22; set rmargin 26
  set label 3 '|---| ' . {{overlays.bands.0.label}} . '   ==== ' . {{overlays.bands.1.label}} \
      at graph 0, screen 0 offset 0,0.5 left
  set yrange [n+0.5:0.5]
  unset ytics
  do for [i=1:|YL|] { set label 100+i YL[i] at graph 0, first i offset -1,0 right }
  do for [i=1:|RL|] { set label 10+i offset 2,0 }
  m = 2 * {{text_width}}
  unset key
  plot \
    $data using 'ref_x':'index':(column('ref_x2') - column('ref_x')):(0) with vectors nohead, \
    $data using 'ref_x':'index':('|') with labels, \
    $data using 'ref_x2':'index':('|') with labels, \
    for [k=0:m] $data using (x = real(k) / m, x >= column('opt_x') && x <= column('opt_x2') ? x : NaN):'index' \
        with points pointtype '=', \
    $data using 'pos':'index':'glyph' with labels textcolor rgb {{colors.ink}}
} else {
  # The chart, then the key alone in a full-width plot below it so its
  # entries can spread across the figure.
  set multiplot
  unset key
  plot \
    $data using (0.5):'index':(0):(1):(column('index')-h):(column('index')+h) with boxxyerror \
        fillcolor rgb {{colors.grid}} fillstyle transparent solid 0.55 noborder, \
    $data using (0.5):'index':'ref_x':'ref_x2':(column('index')-h):(column('index')+h) with boxxyerror \
        fillcolor rgb {{overlays.bands.0.color}} fillstyle transparent solid {{overlays.bands.0.opacity}} noborder, \
    $data using (0.5):'index':'opt_x':'opt_x2':(column('index')-h):(column('index')+h) with boxxyerror \
        fillcolor rgb {{overlays.bands.1.color}} fillstyle transparent solid {{overlays.bands.1.opacity}} noborder, \
    $data using 'pos':(column('index')-0.4):(0):(0.8):'rgb' with vectors nohead linewidth 2.5 \
        linecolor rgb variable, \
    for [i=1:|LK|] $data using (strcol('status') eq LK[i] ? column('pos') : NaN):'index' \
        with points pointtype LP[i] pointsize 1.7 linecolor rgb LC[i]
  unset label; unset ytics
  set lmargin at screen 0.03; set rmargin at screen 0.97
  set tmargin at screen 0.1; set bmargin at screen 0.01
  set key inside center center horizontal Left reverse noautotitle textcolor rgb {{colors.secondary}} \
      samplen 1.5 spacing 1.2 width 2
  set yrange [0:1]
  plot \
    2 with lines linecolor rgb {{colors.surface}} notitle, \
    keyentry with boxes fillcolor rgb {{overlays.bands.0.color}} \
        fillstyle transparent solid {{overlays.bands.0.opacity}} noborder title {{overlays.bands.0.label}}, \
    keyentry with boxes fillcolor rgb {{overlays.bands.1.color}} \
        fillstyle transparent solid {{overlays.bands.1.opacity}} noborder title {{overlays.bands.1.label}}, \
    for [i=1:|LK|] keyentry with points pointtype LP[i] pointsize 1.7 linecolor rgb LC[i] title LL[i]
  unset multiplot
}
