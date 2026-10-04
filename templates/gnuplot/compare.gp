# health-chart compare: one marker over time for several people, a line
# and point shape per person (glyph and name in the key), reference and
# optimal bands shaded, each person's latest value annotated.  The
# backend has already chosen the terminal, the output and a
# tab-separated datafile with column headers.

$data << EOD
{{data}}
EOD
$latest << EOD
{{overlays.annotations}}
EOD

array SN = {{series.name}}
array SL = {{series.label}}
array SC = {{series.color}}
array SP = {{series.pt}}
array AC = {{overlays.annotations.series_color}}
array XT = {{x.ticks.sec}}
array XL = {{x.ticks.label}}
text = ({{format}} eq 'text')

set label 1 {{title}} at screen 0.015, screen 1 offset 0,-1.3 left font {{font}}.' Bold,16' textcolor rgb {{colors.ink}}
set label 2 {{subtitle}} at screen 0.015, screen 1 offset 0,-2.8 left font ',12' textcolor rgb {{colors.secondary}}
set tmargin 6
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

# In text mode the bands are left out, so they get no key entry either.
ref_title = text ? '' : {{overlays.ref_label}}
opt_title = text ? '' : {{overlays.opt_label}}

plot \
  keyentry with boxes \
      fillcolor rgb {{colors.ref_band}} fillstyle transparent solid {{style.ref_band_opacity}} noborder \
      title ref_title, \
  keyentry with boxes \
      fillcolor rgb {{colors.opt_band}} fillstyle transparent solid {{style.opt_band_opacity}} noborder \
      title opt_title, \
  for [i=1:|SN|] $data using 'date':(strcol('series') eq SN[i] ? column('value') : NaN) \
      with linespoints linewidth 2 pointtype SP[i] pointsize 1.5 linecolor rgb SC[i] title SL[i], \
  for [i=1:|AC|] $latest every ::(i-1)::(i-1) using 'date':'label_y':'text' \
      with labels right offset -0.8,0 font ',12' textcolor rgb AC[i] notitle
