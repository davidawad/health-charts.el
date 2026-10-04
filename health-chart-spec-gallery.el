;;; health-chart-spec-gallery.el --- Spec bodies of the gallery chart kinds -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; The chartspec/v1 bodies of the kinds adapted from the Vega-Lite
;; example gallery (docs/chart-gallery.md): trend, lollipop, strip,
;; dumbbell, dual and inrange.  Each only derives numbers a template
;; cannot (a linear fit, a value's position in its reference range, a
;; count of draws per status); drawing stays in templates/BACKEND/KIND.
;;
;; RANGE POSITION.  Markers have different units, so the multi-marker
;; kinds (strip, dumbbell) put every value on its marker's own scale
;; where 0 is the reference low and 1 the reference high.  An open
;; reference side is closed at 0 (below) or at a distance mirroring the
;; optimal edge (above); see `health-chart-spec-gallery--scale'.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'health-chart-core)
(require 'health-chart-model)
(require 'health-chart-spec)

;; -----------------------------------------------------------------------
;; Shared pieces
;; -----------------------------------------------------------------------

(defun health-chart-spec-gallery--groups (ms props)
  "(PERSON . GROUPS) for the markers of MS selected by PROPS.
PROPS: :person (default the first), :marker (a name or list), :since and
:until.  A group is (:marker :label :unit :ms :ranges), :ms being the
marker's measurements oldest first with missing ranges filled in."
  (let* ((ms (health-chart-fill-ranges ms))
         (person (health-chart-model--pick ms :person props))
         (mine (health-chart-filter ms :person person :marker (plist-get props :marker)
                                    :since (plist-get props :since)
                                    :until (plist-get props :until))))
    (cons person
          (mapcar (lambda (g)
                    (list :marker (car g)
                          :label (health-chart-marker-label-in (car g) (cdr g))
                          :unit (plist-get (car (last (cdr g))) :unit)
                          :ms (cdr g) :ranges (health-chart-ranges (cdr g))))
                  (health-chart-by-marker mine)))))

(defun health-chart-spec-gallery--scale (ranges)
  "The (LO . HI) that maps to range positions 0 and 1, from RANGES, or nil.
It is the reference range, with an open low side closed at 0 and an open
high side closed as far above the low edge as the optimal low edge (or,
without one, half the low edge) is, doubled."
  (let ((rl (plist-get ranges :ref-low)) (rh (plist-get ranges :ref-high))
        (ol (plist-get ranges :opt-low)) (oh (plist-get ranges :opt-high))
        scale)
    (setq scale
          (cond ((and rl rh) (cons rl rh))
                (rh (cons 0 rh))
                (rl (cons rl (+ rl (* 2 (max (- (or ol (* 1.5 rl)) rl) (* 0.25 (abs rl)))))))
                ((and ol oh) (cons ol oh))
                (oh (cons 0 oh))
                (ol (cons ol (* 2 ol)))))
    (and scale (> (cdr scale) (car scale)) scale)))

(defun health-chart-spec-gallery--norm (v scale)
  "V as a position on SCALE (LO . HI): 0 at LO, 1 at HI."
  (/ (- v (car scale)) (float (- (cdr scale) (car scale)))))

(defun health-chart-spec-gallery--norm-domain (norms)
  "The (LO . HI) display domain for range positions NORMS.
At least -0.1..1.1, widened to the data and snapped to quarters."
  (cons (max -2.0 (/ (ffloor (* 4 (min -0.1 (- (apply #'min norms) 0.06)))) 4))
        (min 3.0 (/ (fceiling (* 4 (max 1.1 (+ (apply #'max norms) 0.06)))) 4))))

(defun health-chart-spec-gallery--band-x (band scale domain)
  "BAND (LO . HI) on SCALE as (X . X2) within DOMAIN, open sides closed; or nil."
  (when band
    (cons (health-chart-spec--round
           (if (car band) (health-chart-spec-gallery--norm (car band) scale) (car domain)) 4)
          (health-chart-spec--round
           (if (cdr band) (health-chart-spec-gallery--norm (cdr band) scale) (cdr domain)) 4))))

(defun health-chart-spec-gallery--band-legend (theme)
  "The two band entries the range-position kinds list in `overlays.bands'.
Colors and opacities come from THEME and `health-chart-spec-style'."
  (vector (list :key "reference" :label "reference range"
                :color (health-chart-spec--color theme 'ref_band)
                :opacity (plist-get health-chart-spec-style :ref_band_opacity))
          (list :key "optimal" :label "optimal range"
                :color (health-chart-spec--color theme 'opt_band)
                :opacity (plist-get health-chart-spec-style :opt_band_opacity))))

(defun health-chart-spec-gallery--position-axes (domain labels)
  "The (:x :y) axes of a range-position chart over DOMAIN, rows named LABELS."
  (list :x (list :type "quantitative" :title "position in reference range"
                 :domain (vector (car domain) (cdr domain)))
        :y (list :type "nominal" :title nil :domain (apply #'vector labels))))

(defun health-chart-spec-gallery--verdict-legend (theme verdicts)
  "Legend entries for the change VERDICTS (symbols or nil) present, in THEME."
  (apply #'vector
         (delq nil
               (mapcar (lambda (v)
                         (when (member v verdicts)
                           (health-chart-spec--legend-entry
                            (if v (symbol-name v) "unknown")
                            (if v (alist-get v health-chart-verdict-glyphs "?") "?")
                            (if v (symbol-name v) "n/a")
                            (health-chart-spec--color
                             theme (if v (health-chart-spec--role v) 'unknown)))))
                       '(improved on-target steady worsened nil)))))

(defun health-chart-spec-gallery--direction (slope span-ratio)
  "A glyph and word for SLOPE.
Flat when SPAN-RATIO (the change over the span, per level) is small."
  (cond ((< (abs span-ratio) 0.02) "→ flat")
        ((> slope 0) "↗ rising")
        (t "↘ falling")))

;; -----------------------------------------------------------------------
;; strip: every draw of every marker on its own range scale
;; -----------------------------------------------------------------------

(defun health-chart-spec-strip (ms props)
  "Spec body of the range strip plot of MS under PROPS.
One row per draw, with its `norm' (range position), `x' (norm clamped to
the display domain), `clipped', and the marker's band extents."
  (pcase-let* ((theme (health-chart-spec--theme props))
               (`(,person . ,all) (health-chart-spec-gallery--groups ms props))
               (groups (seq-filter (lambda (g) (health-chart-spec-gallery--scale (plist-get g :ranges)))
                                   all)))
    (when groups
      (let* ((norms (cl-loop for g in groups
                             for sc = (health-chart-spec-gallery--scale (plist-get g :ranges))
                             append (mapcar (lambda (m) (health-chart-spec-gallery--norm
                                                         (plist-get m :value) sc))
                                            (plist-get g :ms))))
             (dom (health-chart-spec-gallery--norm-domain norms))
             (rows
              (cl-loop
               for g in groups for i from 1
               for sc = (health-chart-spec-gallery--scale (plist-get g :ranges))
               for bands = (health-chart-model--bands (plist-get g :ranges) props)
               for opt = (health-chart-spec-gallery--band-x (plist-get bands :opt) sc dom)
               for n = (length (plist-get g :ms))
               append
               (cl-loop
                for m in (plist-get g :ms) for j from 1
                for norm = (health-chart-spec-gallery--norm (plist-get m :value) sc)
                for x = (health-chart-spec--clamp norm (car dom) (cdr dom))
                collect (health-chart-spec--row
                         m theme ms
                         :index i :draws n
                         :norm (health-chart-spec--round norm 4)
                         :x (health-chart-spec--round x 4)
                         :clipped (if (= x norm) 0 1)
                         :latest (if (= j n) 1 0)
                         :ref_x (and (plist-get bands :ref) 0)
                         :ref_x2 (and (plist-get bands :ref) 1)
                         :opt_x (car opt) :opt_x2 (cdr opt)
                         :ref_range (health-chart-fmt-range (plist-get (plist-get g :ranges) :ref-low)
                                                            (plist-get (plist-get g :ranges) :ref-high))
                         :opt_range (health-chart-fmt-range (plist-get (plist-get g :ranges) :opt-low)
                                                            (plist-get (plist-get g :ranges) :opt-high))
                         :latest_label (format "%s  %s" (health-chart-fmt-value m)
                                               (health-chart-status-label (health-chart-status m)))))))
             (latest (seq-filter (lambda (r) (= 1 (plist-get r :latest))) rows))
             (axes (health-chart-spec-gallery--position-axes
                    dom (mapcar (lambda (r) (plist-get r :label)) latest))))
        (list :title (format "Every draw vs range · %s" (or person "all"))
              :subtitle (format "%d markers, each on its own scale; grey ticks: earlier draws; marker: latest draw"
                                (length groups))
              :height (+ 140 (* 34 (length groups)))
              :x (plist-get axes :x) :y (plist-get axes :y)
              :rows (apply #'vector rows)
              :overlays (health-chart-spec--overlays
                         :bands (health-chart-spec-gallery--band-legend theme))
              :legend (health-chart-spec--status-legend
                       theme (mapcar (lambda (r) (intern (plist-get r :status))) latest))
              :meta (health-chart-spec--meta (apply #'append (mapcar (lambda (g) (plist-get g :ms)) groups))))))))

;; -----------------------------------------------------------------------
;; dumbbell: first draw to last draw on the range scale
;; -----------------------------------------------------------------------

(defun health-chart-spec-dumbbell (ms props)
  "Spec body of the first-to-latest range dumbbell of MS under PROPS.
One row per marker with two or more draws; `norm_before' and
`norm_after' are range positions, the verdict is delta's."
  (pcase-let* ((theme (health-chart-spec--theme props))
               (`(,person . ,all) (health-chart-spec-gallery--groups ms props))
               (groups (seq-filter (lambda (g)
                                     (and (health-chart-spec-gallery--scale (plist-get g :ranges))
                                          (cdr (plist-get g :ms))))
                                   all)))
    (when groups
      (let* ((norms (cl-loop for g in groups
                             for sc = (health-chart-spec-gallery--scale (plist-get g :ranges))
                             append (mapcar (lambda (m) (health-chart-spec-gallery--norm
                                                         (plist-get m :value) sc))
                                            (list (car (plist-get g :ms))
                                                  (car (last (plist-get g :ms)))))))
             (dom (health-chart-spec-gallery--norm-domain norms))
             (out
              (cl-loop
               for g in groups for i from 1
               for sc = (health-chart-spec-gallery--scale (plist-get g :ranges))
               for b = (car (plist-get g :ms))
               for a = (car (last (plist-get g :ms)))
               for bands = (health-chart-model--bands (plist-get g :ranges) props)
               for opt = (health-chart-spec-gallery--band-x (plist-get bands :opt) sc dom)
               for verdict = (health-chart-model--verdict b a)
               for color = (health-chart-spec--color
                            theme (if verdict (health-chart-spec--role verdict) 'unknown))
               for nb = (health-chart-spec-gallery--norm (plist-get b :value) sc)
               for na = (health-chart-spec-gallery--norm (plist-get a :value) sc)
               collect
               (append
                (health-chart-spec--row a theme ms :index i)
                (list :before (plist-get b :value) :after (plist-get a :value)
                      :date_before (plist-get b :date) :date_after (plist-get a :date)
                      :norm_before (health-chart-spec--round nb 4)
                      :norm_after (health-chart-spec--round na 4)
                      :x_before (health-chart-spec--round (health-chart-spec--clamp nb (car dom) (cdr dom)) 4)
                      :x_after (health-chart-spec--round (health-chart-spec--clamp na (car dom) (cdr dom)) 4)
                      :verdict (if verdict (symbol-name verdict) "unknown")
                      :verdict_glyph (if verdict (alist-get verdict health-chart-verdict-glyphs "?") "?")
                      :verdict_label (health-chart-spec--verdict-label verdict)
                      :verdict_color color :verdict_rgb (health-chart-spec--rgb color)
                      :values_label (string-trim-right
                                    (format "%s → %s %s" (health-chart-fmt (plist-get b :value))
                                            (health-chart-fmt (plist-get a :value))
                                            (or (plist-get a :unit) "")))
                      :span_label (format "%s → %s"
                                          (health-chart-format-date (plist-get b :date) "%b %Y")
                                          (health-chart-format-date (plist-get a :date) "%b %Y"))
                      :text (format "%s  %s" (health-chart-spec--verdict-label verdict)
                                    (string-trim-right
                                     (format "%s → %s" (health-chart-fmt (plist-get b :value))
                                             (health-chart-fmt (plist-get a :value)))))
                      :ref_x (and (plist-get bands :ref) 0)
                      :ref_x2 (and (plist-get bands :ref) 1)
                      :opt_x (car opt) :opt_x2 (cdr opt)
                      :ref_range (health-chart-fmt-range (plist-get (plist-get g :ranges) :ref-low)
                                                         (plist-get (plist-get g :ranges) :ref-high))
                      :opt_range (health-chart-fmt-range (plist-get (plist-get g :ranges) :opt-low)
                                                         (plist-get (plist-get g :ranges) :opt-high))))))
             (axes (health-chart-spec-gallery--position-axes
                    dom (mapcar (lambda (r) (plist-get r :label)) out)))
             (all-ms (apply #'append (mapcar (lambda (g) (plist-get g :ms)) groups))))
        (list :title (format "First vs latest draw · %s" (or person "all"))
              :subtitle (format "hollow: first draw; filled: latest, colored by verdict; %s to %s"
                                (car (health-chart-dates all-ms)) (car (last (health-chart-dates all-ms))))
              :height (+ 140 (* 34 (length out)))
              :x (plist-get axes :x) :y (plist-get axes :y)
              :rows (apply #'vector out)
              :overlays (health-chart-spec--overlays
                         :bands (health-chart-spec-gallery--band-legend theme))
              :legend (health-chart-spec-gallery--verdict-legend
                       theme (mapcar (lambda (r) (let ((v (plist-get r :verdict)))
                                                   (and (not (equal v "unknown")) (intern v))))
                                     out))
              :meta (health-chart-spec--meta all-ms))))))

;; -----------------------------------------------------------------------
;; inrange: how many draws sat in each status
;; -----------------------------------------------------------------------

(defconst health-chart-spec-gallery--status-order '(low optimal normal suboptimal high unknown)
  "Left to right: below range, inside it (best first), above it.")

(defun health-chart-spec-inrange (ms props)
  "Spec body of the share of draws per status for each marker of MS, under PROPS.
One row per marker and status that occurs: `x' and `x2' are the segment's
share of that marker's draws (0..1), `count' and `draws' the numbers."
  (pcase-let* ((theme (health-chart-spec--theme props))
               (`(,person . ,groups) (health-chart-spec-gallery--groups ms props)))
    (when groups
      (let* ((summaries
              (mapcar
               (lambda (g)
                 (let* ((draws (plist-get g :ms)) (n (length draws))
                        (statuses (mapcar #'health-chart-status draws))
                        (inside (seq-count (lambda (s) (memq s '(optimal normal suboptimal))) statuses)))
                   (list :group g :n n :statuses statuses :inside inside
                         :label (format "%d/%d in range" inside n))))
               groups))
             ;; worst first: the markers that most need a look head the list
             (ordered (seq-sort-by (lambda (s) (/ (plist-get s :inside) (float (plist-get s :n))))
                                   #'< summaries))
             (rows
              (cl-loop
               for s in ordered for i from 1
               for g = (plist-get s :group)
               for n = (plist-get s :n)
               append
               (let ((x 0))
                 (cl-loop
                  for st in health-chart-spec-gallery--status-order
                  for count = (seq-count (lambda (v) (eq v st)) (plist-get s :statuses))
                  when (> count 0)
                  collect (let ((x0 x) (share (/ count (float n))))
                            (setq x (+ x share))
                            (list :index i :marker (plist-get g :marker) :label (plist-get g :label)
                                  :unit (plist-get g :unit)
                                  :status (symbol-name st) :glyph (health-chart-status-glyph st)
                                  :status_label (health-chart-status-label st)
                                  :color (health-chart-spec--color theme st)
                                  :rgb (health-chart-spec--rgb (health-chart-spec--color theme st))
                                  :count count :draws n
                                  :x (health-chart-spec--round x0 4)
                                  :x2 (health-chart-spec--round x 4)
                                  :mid (health-chart-spec--round (+ x0 (/ share 2)) 4)
                                  :seg_label (if (>= share 0.09) (format "%d" count) "")
                                  :summary (plist-get s :label)
                                  :detail (format "%d of %d draws %s" count n (symbol-name st))))))))
             (present (mapcar (lambda (r) (intern (plist-get r :status))) rows)))
        (list :title (format "Draws by status · %s" (or person "all"))
              :subtitle "share of each marker's draws below, inside and above its reference range; worst first"
              :height (+ 130 (* 34 (length ordered)))
              :x (list :type "quantitative" :title "share of draws" :domain (vector 0 1))
              :y (list :type "nominal" :title nil
                       :domain (apply #'vector (mapcar (lambda (s) (plist-get (plist-get s :group) :label))
                                                       ordered)))
              :rows (apply #'vector rows)
              :legend (health-chart-spec--status-legend theme present)
              :meta (health-chart-spec--meta
                     (apply #'append (mapcar (lambda (g) (plist-get g :ms)) groups))))))))

;; -----------------------------------------------------------------------
;; trend and lollipop: one marker over time, from the series body
;; -----------------------------------------------------------------------

(defun health-chart-spec-gallery--fit (days values)
  "(SLOPE . INTERCEPT-AT-MEAN-DAY) of the least-squares line through DAYS, VALUES.
Nil with fewer than three points or all DAYS equal."
  (let* ((n (length days)))
    (when (>= n 3)
      (let* ((dm (/ (apply #'+ days) (float n))) (vm (/ (apply #'+ values) (float n)))
             (sxx (apply #'+ (mapcar (lambda (d) (expt (- d dm) 2)) days)))
             (sxy (apply #'+ (cl-mapcar (lambda (d v) (* (- d dm) (- v vm))) days values))))
        (when (> sxx 0)
          (list (/ sxy sxx) dm vm))))))

(defun health-chart-spec-trend (ms props)
  "Spec body of one marker's draws with a rolling mean and linear trend, from MS.
Each row gains `roll' (centred mean of up to three draws) and `fit' (the
least-squares line at that date); `layout.trend' words the slope.  PROPS
select the marker as for `health-chart-model-series'."
  (when-let* ((model (apply #'health-chart-model-series ms props)))
    (let* ((theme (health-chart-spec--theme props))
           (body (health-chart-spec--series-body model theme props ms))
           (rows (append (plist-get body :rows) nil))
           (vals (mapcar (lambda (r) (plist-get r :value)) rows))
           (days (mapcar (lambda (r) (health-chart-date-days (plist-get r :date))) rows))
           (fit (health-chart-spec-gallery--fit days vals))
           (n (length rows))
           (unit (plist-get model :unit))
           (per-year (and fit (* 365.25 (car fit))))
           (span (- (car (last days)) (car days)))
           (level (/ (apply #'+ (mapcar #'abs vals)) (max 1 n)))
           (words (and fit (health-chart-spec-gallery--direction
                            (car fit) (/ (* (car fit) span) (max 1e-9 level)))))
           (label (if fit
                      (format "%s %s%s per year" words
                              (health-chart-fmt (abs per-year))
                              (if (string-empty-p (or unit "")) "" (concat " " unit)))
                    "trend needs three draws")))
      (plist-put
       (plist-put
        (plist-put body :rows
                  (apply #'vector
                         (cl-loop
                          for r in rows for i from 0
                          collect
                          (append r (list
                                     :roll (health-chart-spec--round
                                            (let ((w (seq-subseq vals (max 0 (1- i)) (min n (+ i 2)))))
                                              (/ (apply #'+ w) (float (length w))))
                                            4)
                                     :fit (and fit (health-chart-spec--round
                                                    (+ (nth 2 fit) (* (car fit) (- (nth i days) (nth 1 fit))))
                                                    4)))))))
        :layout (list :trend (list :slope_per_year (health-chart-spec--round per-year 4)
                                   :label label :draws n)))
       :subtitle (format "%s · %s (linear fit)" (plist-get body :subtitle) label)))))

(defun health-chart-spec-lollipop (ms props)
  "Spec body of one marker's draws as stems to its target limit, from MS.
`base' is the target's upper limit (else its lower), optimal before
reference; `gap' is the value past it, `gap_label' its words.  PROPS
select the marker as for `health-chart-model-series'."
  (when-let* ((model (apply #'health-chart-model-series ms props)))
    (let* ((theme (health-chart-spec--theme props))
           (target (or (plist-get model :opt) (plist-get model :ref)))
           (edge (or (cdr target) (car target)))
           (vals (mapcar #'cadr (plist-get (car (plist-get model :lines)) :points)))
           (base (or edge (min 0 (apply #'min vals))))
           (rng (plist-get model :y-range))
           (pad (* 0.05 (- (cdr rng) (car rng))))
           (model (plist-put (copy-sequence model) :y-range
                             ;; headroom above the tallest stem for its label
                             (cons (min (car rng) (- base pad))
                                   (+ (max (cdr rng) (+ base pad)) (* 2 pad)))))
           (body (health-chart-spec--series-body model theme props ms))
           (unit (plist-get model :unit))
           (word (cond ((null edge) "baseline") ((plist-get model :opt) "optimal") (t "reference")))
           (limit (if (cdr target) "limit" "minimum")))
      (plist-put
       (plist-put
        (plist-put
         body :subtitle
         (format "%s · stems run from the %s %s %s%s" (plist-get body :subtitle) word limit
                 (health-chart-fmt base) (if (string-empty-p (or unit "")) "" (concat " " unit))))
        :rows
        (apply #'vector
               (mapcar (lambda (r)
                         (let ((gap (- (plist-get r :value) base)))
                           (append r (list :base (health-chart-spec--round base)
                                           :gap (health-chart-spec--round gap 4)
                                           :gap_label (format "%s%s" (if (>= gap 0) "+" "−")
                                                              (health-chart-fmt (abs gap)))))))
                       (plist-get body :rows))))
       :overlays (append (cl-loop for (k v) on (plist-get body :overlays) by #'cddr
                                  append (list k (if (eq k :thresholds)
                                                     (vector (list :value (health-chart-spec--round base)
                                                                   :label (format "%s %s %s%s" word limit
                                                                                  (health-chart-fmt base)
                                                                                  (if (string-empty-p (or unit ""))
                                                                                      "" (concat " " unit)))
                                                                   :axis "y"
                                                                   :color (health-chart-spec--color theme 'secondary)))
                                                   v))))))))

;; -----------------------------------------------------------------------
;; dual: two markers, two axes
;; -----------------------------------------------------------------------

(defun health-chart-spec-gallery--dual-markers (ms props)
  "The two marker names a dual chart draws, from MS and PROPS.
PROPS' :marker list, else glucose and HbA1c when present, else the first
two markers of MS."
  (let ((picked (plist-get props :marker)))
    (cond ((and (listp picked) (cdr picked)) (seq-take picked 2))
          (t (let ((all (health-chart-markers ms)))
               (if (and (member "glucose" all) (member "hba1c" all)) '("glucose" "hba1c")
                 (seq-take all 2)))))))

(defun health-chart--check-dual (data props)
  "Signal unless a dual chart can pick two markers of DATA under PROPS."
  (let* ((picked (plist-get props :marker))
         (present (health-chart-markers data))
         (two (health-chart-spec-gallery--dual-markers data props)))
    (when (or (< (length two) 2)
              (and picked (listp picked) (/= (length picked) 2)))
      (signal 'health-chart-invalid-data
              (list (format ":marker must name two markers for a dual-axis chart; markers present: %s"
                            (string-join present ", "))
                    :code "invalid_prop")))
    (dolist (m two)
      (unless (member m present)
        (signal 'health-chart-invalid-data
                (list (format "no measurements for marker %S; markers present: %s" m
                              (string-join present ", "))
                      :code "unknown_marker" :marker m))))))

(defun health-chart-spec-dual (ms props)
  "Spec body overlaying two markers of MS on a left and a right axis, under PROPS."
  (let* ((theme (health-chart-spec--theme props))
         (names (health-chart-spec-gallery--dual-markers ms props))
         (person (health-chart-model--pick ms :person props))
         (palette (or (alist-get 'series health-chart-colors)
                      (alist-get 'series (health-chart-spec--palette theme))))
         (inks (list (nth 0 palette) (nth (min 6 (1- (length palette))) palette)))
         (models (mapcar (lambda (name)
                           (apply #'health-chart-model-series ms :marker name :person person
                                  (health-chart--plist-drop props :marker :person)))
                         names)))
    (when (and (= 2 (length models)) (cl-every #'identity models))
      (let* ((sides '("left" "right"))
             (series
              (cl-loop for model in models for side in sides for ink in inks
                       for range = (health-chart-spec--floor-zero
                                    (plist-get model :y-range)
                                    (mapcar #'cadr (plist-get (car (plist-get model :lines)) :points)))
                       for latest = (plist-get model :latest)
                       collect (list :name (plist-get model :marker) :axis side
                                     :label (format "%s (%s axis)" (plist-get model :label) side)
                                     :title (if (string-empty-p (or (plist-get model :unit) ""))
                                                (plist-get model :label)
                                              (format "%s (%s)" (plist-get model :label)
                                                      (plist-get model :unit)))
                                     :unit (plist-get model :unit)
                                     :color ink :rgb (health-chart-spec--rgb ink)
                                     :domain (vector (health-chart-spec--round (car range))
                                                     (health-chart-spec--round (cdr range)))
                                     :latest_label (format "%s %s  %s" (plist-get model :label)
                                                           (health-chart-fmt-value latest)
                                                           (health-chart-status-label
                                                            (health-chart-status latest))))))
             (rows (cl-loop
                    for model in models for s in series
                    append (let* ((pts (plist-get (car (plist-get model :lines)) :points))
                                  (n (length pts)))
                             (cl-loop for p in pts for i from 1
                                      collect (health-chart-spec--row
                                               (cl-third p) theme ms
                                               :series (plist-get s :name)
                                               :series_label (plist-get s :label)
                                               :series_color (plist-get s :color)
                                               :axis (plist-get s :axis)
                                               :latest (if (= i n) 1 0))))))
             (chosen (mapcar (lambda (r) (list :date (plist-get r :date))) rows))
             (thresholds
              (apply #'vector
                     (delq nil
                           (cl-loop for model in models for s in series
                                    collect
                                    (let* ((target (or (plist-get model :ref) (plist-get model :opt)))
                                           (edge (or (cdr target) (car target))))
                                      (when edge
                                        (list :value edge :axis (plist-get s :axis)
                                              :label (format "%s %s%s" (plist-get model :label)
                                                             (if (cdr target) "≤" "≥")
                                                             (health-chart-fmt edge))
                                              :color (plist-get s :color))))))))
             (annotations
              (apply #'vector
                     (cl-loop for model in models for s in series
                              collect (append (health-chart-spec--latest-annotation
                                               (plist-get model :latest) theme)
                                              (list :axis (plist-get s :axis)
                                                    :series (plist-get s :name)
                                                    :series_color (plist-get s :color)
                                                    :text (plist-get s :latest_label)))))))
        (list :title (format "%s · %s · %s" (plist-get (nth 0 models) :label)
                             (plist-get (nth 1 models) :label) (or person "all"))
              :subtitle (concat "latest: " (string-join (mapcar (lambda (s) (plist-get s :latest_label)) series) " · "))
              :x (health-chart-spec--date-axis (health-chart-dates chosen) nil
                                               (health-chart-spec--width props))
              :y (health-chart-spec--value-axis nil nil)
              :layout (list :left (nth 0 series) :right (nth 1 series))
              :rows (apply #'vector rows)
              :overlays (health-chart-spec--overlays :thresholds thresholds :annotations annotations)
              :legend (health-chart-spec--status-legend
                       theme (mapcar (lambda (r) (intern (plist-get r :status))) rows))
              :series (apply #'vector series)
              :meta (health-chart-spec--meta
                     (apply #'append (mapcar (lambda (m) (mapcar #'cl-third (plist-get (car (plist-get m :lines)) :points)))
                                             models))))))))

(provide 'health-chart-spec-gallery)
;;; health-chart-spec-gallery.el ends here
