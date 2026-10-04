# health-chart panel: small multiples, one compact time series per
# marker on its own y scale, reference and optimal bands shaded, points
# by status (shape + color; glyph and word in the key), the latest value
# and status above each cell.  The backend has already chosen the
# terminal, the output and a tab-separated datafile with column headers.

$data << EOD
{{data}}
EOD

array PM = {{panels.marker}}
array PT = {{panels.title}}
array PL = {{panels.latest_label}}
array PY0 = {{panels.y_min}}
array PY1 = {{panels.y_max}}
array PR0 = {{panels.ref_y}}
array PR1 = {{panels.ref_y2}}
array PO0 = {{panels.opt_y}}
array PO1 = {{panels.opt_y2}}
array PC = {{panels.column}}
array PR = {{panels.row}}
array LK = {{legend.key}}
array LL = {{legend.label}}
array LC = {{legend.color}}
array LP = {{legend.pt}}
array XT = {{x.ticks.sec}}
array XL = {{x.ticks.label}}
text = ({{format}} eq 'text')
ncol = {{layout.columns}}
nrow = {{layout.rows}}

# Figure geometry in screen fractions, from the spec's pixel size: the
# title block on top, the key below, then one cell per panel with room
# for its header (title, latest value) above and date labels below.
W = {{width}}.0
H = {{height}}.0
top = 1 - 84 / H
bottom = 64 / H
left = 0.015
right = 0.985
if (text) {
  th = 9 * nrow + 3
  set terminal dumb noenhanced size {{text_width}}, th
  H = th; W = {{text_width}}
  top = 1 - 1.5 / H; bottom = 1.5 / H; left = 0.0; right = 1.0
}
colw = (right - left) / ncol
rowh = (top - bottom) / nrow
padtop = (text ? 2.0 : 56) / H
padbot = (text ? 1.0 : 36) / H
padl = (text ? 7.0 : 46) / W
padr = (text ? 2.0 : 20) / W

set label 1 {{title}} at screen 0.015, screen 1 offset 0,-1.3 left font {{font}}.' Bold,16' textcolor rgb {{colors.ink}}
set label 2 {{subtitle}} at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb {{colors.secondary}}
if (text) { unset label 2; set label 1 at screen 0, screen 1 offset 0,-0.5 }

set border 3 linecolor rgb {{colors.axis}}
set tics nomirror textcolor rgb {{colors.secondary}} font ',9.5'
set grid ytics linetype 1 linecolor rgb {{colors.grid}} linewidth 1
set grid noxtics
unset key
set xdata time
set timefmt '%Y-%m-%d'
set xrange [{{x.domain.0}}:{{x.domain.1}}]
set xtics ()
do for [i=1:|XT|] { set xtics add (XL[i] XT[i]) }
set ytics scale 0.5
set xtics scale 0.5
set ylabel
if (text) {
  unset grid; set ytics scale 0; set xtics scale 0
  # short date labels so a narrow cell's ticks stay apart: '22 or Nov
  set xtics ()
  do for [i=1:|XT|] { set xtics add ((strlen(XL[i]) == 4 ? "'" . XL[i][3:4] : XL[i][1:3]) XT[i]) }
}

set multiplot
do for [i=1:|PM|] {
  x0 = left + (PC[i] - 1) * colw
  y1 = top - (PR[i] - 1) * rowh
  set lmargin at screen x0 + padl
  set rmargin at screen x0 + colw - padr
  set tmargin at screen y1 - padtop
  set bmargin at screen y1 - rowh + padbot
  set yrange [PY0[i]:PY1[i]]
  # about four y ticks on a 1-2-5 step
  r = (PY1[i] - PY0[i]) / 4.0
  e = 10.0 ** floor(log10(r))
  f = r / e
  step = (f < 1.5 ? 1 : f < 3 ? 2 : f < 7 ? 5 : 10) * e
  set ytics ceil(PY0[i] / step) * step, step
  unset object 1
  unset object 2
  if (!text && PR0[i] == PR0[i]) {
    set object 1 rect from graph 0, first PR0[i] to graph 1, first PR1[i] \
        behind fillcolor rgb {{colors.ref_band}} fillstyle transparent solid {{style.ref_band_opacity}} noborder
  }
  if (!text && PO0[i] == PO0[i]) {
    set object 2 rect from graph 0, first PO0[i] to graph 1, first PO1[i] \
        behind fillcolor rgb {{colors.opt_band}} fillstyle transparent solid {{style.opt_band_opacity}} noborder
  }
  if (text) {
    set label 11 PT[i] at graph 0, graph 1 offset -5,1 left
    plot $data using 'date':(strcol('marker') eq PM[i] ? column('value') : NaN) with lines linetype 1, \
         $data using 'date':(strcol('marker') eq PM[i] ? column('value') : NaN):'glyph' with labels
  } else {
    set label 11 PT[i] at graph 0, graph 1 offset -0.5,2.1 left font ({{font}} . ' Bold,11.5') textcolor rgb {{colors.ink}}
    set label 12 PL[i] at graph 1, graph 1 offset 0,0.9 right font ',10.5' textcolor rgb {{colors.secondary}}
    plot \
      $data using 'date':(strcol('marker') eq PM[i] ? column('value') : NaN) \
          with lines linewidth 1.6 linecolor rgb {{colors.muted}}, \
      for [k=1:|LK|] $data using 'date':(strcol('marker') eq PM[i] && strcol('status') eq LK[k] ? column('value') : NaN) \
          with points pointtype LP[k] pointsize 1.1 linecolor rgb LC[k]
  }
  if (i == 1) { unset label 1; unset label 2 }
}

# The key alone, in a full-width strip at the bottom of the figure.
if (text) {
  key = ''
  do for [i=1:|LL|] { key = key . LL[i] . '   ' }
  set label 3 key at screen 0, screen 0 offset 1,0.5 left
} else {
  unset label 11; unset label 12; unset label 3
}
unset object 1; unset object 2
unset border; unset tics; unset grid; unset xdata
set lmargin at screen 0.03; set rmargin at screen 0.97
set tmargin at screen bottom - 8 / H; set bmargin at screen 0.005
set xrange [0:1]; set yrange [0:1]
set key inside center center horizontal Left reverse noautotitle textcolor rgb {{colors.secondary}} \
    samplen 1.5 spacing 1.2 width 2
if (text) {
  unset key
  set tmargin at screen 0.5 / H
  plot 2 notitle
} else {
  plot 2 with lines linecolor rgb {{colors.surface}} notitle, \
    keyentry with boxes fillcolor rgb {{colors.ref_band}} fillstyle transparent solid {{style.ref_band_opacity}} \
        noborder title {{overlays.bands.0.label}}, \
    keyentry with boxes fillcolor rgb {{colors.opt_band}} fillstyle transparent solid {{style.opt_band_opacity}} \
        noborder title {{overlays.bands.1.label}}, \
    for [k=1:|LK|] keyentry with points pointtype LP[k] pointsize 1.3 linecolor rgb LC[k] title LL[k]
}
unset multiplot
