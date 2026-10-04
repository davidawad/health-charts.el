# health-chart timeseries: one marker over time, reference and optimal
# bands shaded, points by status (shape + color, glyph and word in the
# key), latest value annotated.  The backend has already chosen the
# terminal, the output and a tab-separated datafile with column headers.

$data << EOD
{{data}}
EOD
$latest << EOD
{{overlays.annotations}}
EOD

array LK = {{legend.key}}
array LL = {{legend.label}}
array LC = {{legend.color}}
array LP = {{legend.pt}}
array XT = {{x.ticks.sec}}
array XL = {{x.ticks.label}}
text = ({{format}} eq 'text')

set label 1 {{title}} at screen 0.015, screen 1 offset 0,-1.3 left font {{font}}.' Bold,16' textcolor rgb {{colors.ink}}
set label 2 {{subtitle}} at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb {{colors.secondary}}
set tmargin 5
set rmargin 4
set border 3 linecolor rgb {{colors.axis}}
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
set yrange [{{y.domain.0}}:{{y.domain.1}}]
set ylabel {{y.title}} textcolor rgb {{colors.secondary}}

if (!text && {{overlays.ref_y}} == {{overlays.ref_y}}) {
  set object 1 rect from graph 0, first {{overlays.ref_y}} to graph 1, first {{overlays.ref_y2}} \
      behind fillcolor rgb {{colors.ref_band}} fillstyle transparent solid {{style.ref_band_opacity}} noborder
}
if (!text && {{overlays.opt_y}} == {{overlays.opt_y}}) {
  set object 2 rect from graph 0, first {{overlays.opt_y}} to graph 1, first {{overlays.opt_y2}} \
      behind fillcolor rgb {{colors.opt_band}} fillstyle transparent solid {{style.opt_band_opacity}} noborder
}

plot \
  keyentry with boxes \
      fillcolor rgb {{colors.ref_band}} fillstyle transparent solid {{style.ref_band_opacity}} noborder \
      title {{overlays.ref_label}}, \
  keyentry with boxes \
      fillcolor rgb {{colors.opt_band}} fillstyle transparent solid {{style.opt_band_opacity}} noborder \
      title {{overlays.opt_label}}, \
  $data using 'date':'value' with lines linewidth 2 linecolor rgb {{colors.muted}} notitle, \
  for [i=1:|LK|] $data using 'date':(strcol('status') eq LK[i] ? column('value') : NaN) \
      with points pointtype LP[i] pointsize 1.6 linecolor rgb LC[i] title LL[i], \
  $latest using 'date':'value':'text' with labels right offset -1,1.2 font {{font}}.' Bold,12' \
      textcolor rgb {{colors.ink}} notitle
