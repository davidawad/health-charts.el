# health-chart dumbbell: per marker, the first draw (hollow) to the latest
# (filled, colored by verdict; glyph and word in the label and key) on
# the marker's own range scale (0 = reference low, 1 = reference high).
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
h = 0.31
x1 = {{x.domain.1}}

set label 1 {{title}} at screen 0.015, screen 1 offset 0,-1.3 left font {{font}}.' Bold,16' textcolor rgb {{colors.ink}}
set label 2 {{subtitle}} at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb {{colors.secondary}}
set tmargin 6
set lmargin 17
set rmargin 27
set border 0
set xrange [{{x.domain.0}}:{{x.domain.1}}]
set yrange [n+0.7:0.3]
set xtics scale 0 nomirror textcolor rgb {{colors.secondary}} offset 0,-0.3
set xtics ()
set xtics add ('reference low' 0, 'reference high' 1)
set xlabel {{x.title}} textcolor rgb {{colors.secondary}} offset 0,0.3
set ytics scale 0 nomirror textcolor rgb {{colors.ink}} offset -0.5,0
set ytics ()
do for [i=1:n] { set ytics add (YL[i] i) }
set bmargin 9
set key outside bottom center horizontal Left reverse noautotitle textcolor rgb {{colors.secondary}} samplen 1.5 spacing 1.2 width 1

if (text) {
  unset label 2
  set label 1 at screen 0, screen 1 offset 0,-0.5
  set terminal dumb noenhanced size {{text_width}}, n + 8
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
      with boxxyerror fillcolor rgb {{overlays.bands.0.color}} fillstyle transparent solid {{overlays.bands.0.opacity}} noborder, \
  $data using (column('opt_x') == column('opt_x') ? 0.5 : NaN):'index':'opt_x':'opt_x2':(column('index')-h):(column('index')+h) \
      with boxxyerror fillcolor rgb {{overlays.bands.1.color}} fillstyle transparent solid {{overlays.bands.1.opacity}} noborder, \
  $data using 'x_before':'index':(column('x_after') - column('x_before')):(0):'verdict_rgb' \
      with vectors nohead linewidth 3 linecolor rgb variable, \
  $data using 'x_before':'index' with points pointtype 7 pointsize 1.5 linecolor rgb {{colors.surface}}, \
  $data using 'x_before':'index' with points pointtype 6 pointsize 1.5 linewidth 2 linecolor rgb {{colors.secondary}}, \
  for [i=1:|LK|] $data using (strcol('verdict_label') eq LL[i] ? column('x_after') : NaN):'index' \
      with points pointtype 7 pointsize 1.9 linecolor rgb LC[i], \
  $data using (x1):'index':'text' with labels left offset 1.5,0 textcolor rgb {{colors.ink}}
if (!text) {
  unset label; unset ytics; unset xtics; unset xlabel
  set lmargin at screen 0.03; set rmargin at screen 0.97
  set tmargin at screen 0.1; set bmargin at screen 0.01
  set key inside center center horizontal Left reverse noautotitle textcolor rgb {{colors.secondary}} \
      samplen 1.5 spacing 1.2 width 2
  set xrange [0:1]; set yrange [0:1]
  plot \
    2 with lines linecolor rgb {{colors.surface}} notitle, \
    keyentry with boxes fillcolor rgb {{overlays.bands.0.color}} \
        fillstyle transparent solid {{overlays.bands.0.opacity}} noborder title {{overlays.bands.0.label}}, \
    keyentry with boxes fillcolor rgb {{overlays.bands.1.color}} \
        fillstyle transparent solid {{overlays.bands.1.opacity}} noborder title {{overlays.bands.1.label}}, \
    keyentry with points pointtype 6 pointsize 1.5 linewidth 2 linecolor rgb {{colors.secondary}} title 'first draw', \
    for [i=1:|LK|] keyentry with boxes fillcolor rgb LC[i] fillstyle solid noborder title LL[i]
  unset multiplot
}
