;;; health-chart-svg.el --- SVG renderers for health-chart -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Every chart kind as an SVG document, built with Emacs's own svg.el
;; from the same models as the text backend.  Colors come from one
;; palette with selected light and dark variants: reserved status colors
;; (good / warning / critical) always travel with a glyph and a word, the
;; reference band is a neutral wash and the optimal band a green one,
;; and overlaid people take categorical hues in fixed order.  Every
;; point, bar and cell carries a hover <title>.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'svg)
(require 'health-chart-core)
(require 'health-chart-model)

(defcustom health-chart-svg-width 640
  "Default SVG chart width in pixels."
  :type 'natnum
  :group 'health-charts)

(defcustom health-chart-svg-height 280
  "Default SVG time-series height in pixels."
  :type 'natnum
  :group 'health-charts)

(defcustom health-chart-svg-theme 'auto
  "SVG palette: `light', `dark', or `auto' (follow the frame background)."
  :type '(choice (const auto) (const light) (const dark))
  :group 'health-charts)

(defcustom health-chart-svg-colors nil
  "Per-role color overrides, (ROLE . \"#rrggbb\"), on top of the theme.
Roles: surface ink secondary muted grid axis ref-band opt-band good
warning critical normal series (a list of colors)."
  :type '(alist :key-type symbol :value-type sexp)
  :group 'health-charts)

(defcustom health-chart-svg-font-family "system-ui, -apple-system, Segoe UI, sans-serif"
  "CSS font-family for all SVG text."
  :type 'string
  :group 'health-charts)

(defcustom health-chart-svg-font-size 12
  "Font size in pixels for SVG text."
  :type 'natnum
  :group 'health-charts)

(defconst health-chart-svg-palettes
  '((light (surface . "#fcfcfb") (ink . "#0b0b0b") (secondary . "#52514e")
           (muted . "#898781") (grid . "#e1e0d9") (axis . "#c3c2b7")
           (ref-band . "#e1e0d9") (opt-band . "#0ca30c")
           (good . "#0ca30c") (warning . "#fab219") (critical . "#d03b3b")
           (normal . "#2a78d6")
           (series "#2a78d6" "#eb6834" "#1baf7a" "#eda100"
                   "#e87ba4" "#008300" "#4a3aa7" "#e34948"))
    (dark (surface . "#1a1a19") (ink . "#ffffff") (secondary . "#c3c2b7")
          (muted . "#898781") (grid . "#2c2c2a") (axis . "#383835")
          (ref-band . "#383835") (opt-band . "#0ca30c")
          (good . "#0ca30c") (warning . "#fab219") (critical . "#d03b3b")
          (normal . "#3987e5")
          (series "#3987e5" "#d95926" "#199e70" "#c98500"
                  "#d55181" "#008300" "#9085e9" "#e66767")))
  "Selected light and dark palettes, role -> color.")

(defun health-chart-svg--theme ()
  "The concrete palette name for `health-chart-svg-theme'."
  (if (memq health-chart-svg-theme '(light dark))
      health-chart-svg-theme
    (if (and (display-graphic-p) (eq (frame-parameter nil 'background-mode) 'dark))
        'dark 'light)))

(defun health-chart-svg--c (role)
  "Color for palette ROLE."
  (or (alist-get role health-chart-svg-colors)
      (alist-get role (alist-get (health-chart-svg--theme) health-chart-svg-palettes))))

(defun health-chart-svg--series-color (i)
  "Categorical color for series I, in fixed order."
  (let ((colors (health-chart-svg--c 'series)))
    (nth (mod i (length colors)) colors)))

(defun health-chart-svg--status-color (status)
  "Fill color for STATUS."
  (health-chart-svg--c (pcase status
                         ('optimal 'good) ('suboptimal 'warning)
                         ((or 'low 'high) 'critical) ('normal 'normal)
                         (_ 'muted))))

;; -----------------------------------------------------------------------
;; Primitives
;; -----------------------------------------------------------------------

(defun health-chart-svg--n (x)
  "X rounded to two decimals, for stable SVG coordinates."
  (/ (round (* x 100)) 100.0))

(defun health-chart-svg--string (svg)
  "SVG serialized to a string, identical on every Emacs build."
  (replace-regexp-in-string
   "[ \t\n]*\\(<\\|>\\)[ \t\n]*" "\\1"
   (with-temp-buffer (svg-print svg) (buffer-string))))

(cl-defun health-chart-svg--text (svg text x y &key (anchor "start") color size weight)
  "Add TEXT to SVG at X,Y; ANCHOR, COLOR (default ink), SIZE, WEIGHT."
  (apply #'svg-text svg text
         :x (health-chart-svg--n x) :y (health-chart-svg--n y)
         :font-family health-chart-svg-font-family
         :font-size (or size health-chart-svg-font-size)
         :text-anchor anchor :fill (or color (health-chart-svg--c 'ink))
         (when weight (list :font-weight weight))))

(defun health-chart-svg--group (svg title)
  "A new group in SVG whose hover title is TITLE; return it."
  (let ((node (svg-node svg 'g)))
    (setcdr (cdr node) (append (cddr node) (list (list 'title nil (format "%s" title)))))
    node))

(defun health-chart-svg--canvas (width height title)
  "A WIDTH x HEIGHT svg on the chart surface, with TITLE text when non-nil."
  (let ((svg (svg-create width height)))
    (svg-rectangle svg 0 0 width height :fill (health-chart-svg--c 'surface))
    (when title
      (health-chart-svg--text svg title 12 22 :size (+ health-chart-svg-font-size 2)
                              :weight "bold"))
    svg))

;; -----------------------------------------------------------------------
;; Series box: timeseries, compare and each panel cell
;; -----------------------------------------------------------------------

(defun health-chart-svg--band (svg band lo hi sy x w color opacity)
  "Shade BAND of LO..HI in SVG, scaled by SY, at X across W in COLOR.
BAND is (LO . HI), nil bounds open; OPACITY is the fill opacity."
  (when band
    (let* ((top (funcall sy (min hi (or (cdr band) hi))))
           (bottom (funcall sy (max lo (or (car band) lo)))))
      (when (> bottom top)
        (svg-rectangle svg x top w (health-chart-svg--n (- bottom top))
                       :fill color :fill-opacity opacity)))))

(defun health-chart-svg--x-labels (dates sx compact)
  "List of (X LABEL ANCHOR) for draw DATES placed by SX, never overlapping.
COMPACT abbreviates to year-month.  The first and last dates always show."
  (let* ((fmt (if compact "%y-%m" health-chart-date-format))
         (size (- health-chart-svg-font-size (if compact 1 0)))
         (items (mapcar (lambda (d) (cons (funcall sx (health-chart-date-days d))
                                          (health-chart-format-date d fmt)))
                        (delete-dups (copy-sequence dates))))
         (n (length items))
         kept)
    (cl-loop
     for (x . label) in items for i from 0
     for anchor = (cond ((= n 1) "middle") ((= i 0) "start") ((= i (1- n)) "end") (t "middle"))
     for w = (* size 0.62 (length label))
     for left = (pcase anchor ("start" x) ("end" (- x w)) (_ (- x (/ w 2))))
     do (progn
          (when (= i (1- n))
            (while (and kept (< left (+ (nth 3 (car kept)) 8)) (cdr kept))
              (pop kept)))
          (when (or (null kept) (>= left (+ (nth 3 (car kept)) 8)))
            (push (list x label anchor (+ left w)) kept))))
    (mapcar (lambda (k) (seq-take k 3)) (nreverse kept))))

(defun health-chart-svg--series-box (svg model x y w h &optional compact)
  "Draw series MODEL into SVG in the box X,Y,W,H.
COMPACT uses fewer labels, for panel cells."
  (pcase-let* ((left (if compact 36 48)) (bottom 20)
               (right (if (and (plist-get model :compare) (not compact)) 56 14))
               (px (+ x left)) (pw (max 10 (- w left right)))
               (py y) (ph (max 10 (- h bottom)))
               (`(,lo . ,hi) (plist-get model :y-range))
               (`(,d0 . ,d1) (plist-get model :x-range))
               (sy (lambda (v) (health-chart-svg--n (+ py (* ph (- 1 (/ (- v lo) (float (- hi lo)))))))))
               (sx (lambda (d) (health-chart-svg--n
                                (if (= d0 d1) (+ px (/ pw 2.0))
                                  (+ px (* pw (/ (- d d0) (float (- d1 d0))))))))))
    (health-chart-svg--band svg (plist-get model :ref) lo hi sy px pw
                            (health-chart-svg--c 'ref-band) 0.7)
    (health-chart-svg--band svg (plist-get model :opt) lo hi sy px pw
                            (health-chart-svg--c 'opt-band) 0.16)
    (dolist (v (health-chart-nice-ticks lo hi (if compact 3 5)))
      (let ((ty (funcall sy v)))
        (svg-line svg px ty (+ px pw) ty :stroke (health-chart-svg--c 'grid) :stroke-width 1)
        (health-chart-svg--text svg (health-chart-fmt v) (- px 6) (+ ty 4)
                                :anchor "end" :color (health-chart-svg--c 'muted)
                                :size (- health-chart-svg-font-size (if compact 1 0)))))
    (svg-line svg px (+ py ph) (+ px pw) (+ py ph) :stroke (health-chart-svg--c 'axis) :stroke-width 1)
    (let ((dates (mapcar (lambda (p) (plist-get (nth 2 p) :date))
                         (apply #'append (mapcar (lambda (l) (plist-get l :points))
                                                 (plist-get model :lines))))))
      (pcase-dolist (`(,lx ,label ,anchor) (health-chart-svg--x-labels (sort dates #'string<) sx compact))
        (health-chart-svg--text svg label lx (+ py ph 15) :anchor anchor
                                :color (health-chart-svg--c 'muted)
                                :size (- health-chart-svg-font-size (if compact 1 0)))))
    (cl-loop
     for line in (plist-get model :lines) for i from 0
     for compare = (plist-get model :compare)
     for color = (if compare (health-chart-svg--series-color i) (health-chart-svg--c 'normal))
     for pts = (mapcar (lambda (p) (cons (funcall sx (nth 0 p)) (funcall sy (nth 1 p))))
                       (plist-get line :points))
     do (when (cdr pts)
          (svg-polyline svg pts :fill "none" :stroke color :stroke-width 2
                        :stroke-linejoin "round" :stroke-linecap "round"))
     do (cl-loop for p in (plist-get line :points) for xy in pts
                 for m = (nth 2 p) for status = (health-chart-status m)
                 do (svg-circle (health-chart-svg--group
                                 svg (format "%s%s %s: %s (%s)"
                                             (if compare (format "%s · " (plist-get line :name)) "")
                                             (plist-get model :label)
                                             (plist-get m :date) (health-chart-fmt-value m)
                                             (health-chart-status-label status)))
                                (car xy) (cdr xy) (if compact 3.5 4.5)
                                :fill (if compare color (health-chart-svg--status-color status))
                                :stroke (health-chart-svg--c 'surface) :stroke-width 2))
     do (when (and compare pts (not compact))
          (let ((end (car (last pts))))
            (health-chart-svg--text svg (format "%s" (or (plist-get line :name) "?"))
                                    (+ (car end) 7) (+ (cdr end) 4)
                                    :color (health-chart-svg--c 'secondary)
                                    :size (1- health-chart-svg-font-size)))))))

(defun health-chart-svg--legend (svg model x y)
  "Legend for series MODEL at X,Y in SVG: people (compare) and bands."
  (let ((cursor x)
        (fs (1- health-chart-svg-font-size)))
    (cl-flet ((swatch (draw label)
                (funcall draw cursor)
                (health-chart-svg--text svg label (+ cursor 16) (+ y 4)
                                        :color (health-chart-svg--c 'secondary) :size fs)
                (setq cursor (+ cursor 28 (* fs 0.6 (string-width label))))))
      (when (plist-get model :compare)
        (cl-loop for line in (plist-get model :lines) for i from 0
                 for color = (health-chart-svg--series-color i)
                 do (swatch (lambda (cx) (svg-line svg cx y (+ cx 12) y :stroke color :stroke-width 2))
                            (format "%s" (or (plist-get line :name) "?")))))
      (when-let* ((opt (plist-get model :opt)))
        (swatch (lambda (cx) (svg-rectangle svg cx (- y 5) 12 10 :fill (health-chart-svg--c 'opt-band)
                                            :fill-opacity 0.3))
                (format "optimal %s" (health-chart-fmt-range (car opt) (cdr opt)))))
      (when-let* ((ref (plist-get model :ref)))
        (swatch (lambda (cx) (svg-rectangle svg cx (- y 5) 12 10 :fill (health-chart-svg--c 'ref-band)))
                (format "reference %s" (health-chart-fmt-range (car ref) (cdr ref))))))))

(defun health-chart-svg--series-title (model)
  "Title string for series MODEL."
  (let ((latest (plist-get model :latest)))
    (concat (plist-get model :label)
            (if (plist-get model :person) (format " · %s" (plist-get model :person)) "")
            (if (plist-get model :compare) ""
              (format " — latest %s (%s) %s" (health-chart-fmt-value latest)
                      (plist-get latest :date)
                      (health-chart-status-label (health-chart-status latest)))))))

(defun health-chart-svg--series-chart (model width height title)
  "Full SVG document for series MODEL, WIDTH x HEIGHT, TITLE or a derived one."
  (when model
    (let* ((svg (health-chart-svg--canvas width height (or title (health-chart-svg--series-title model)))))
      (health-chart-svg--legend svg model 14 44)
      (health-chart-svg--series-box svg model 0 60 width (- height 66))
      (health-chart-svg--string svg))))

(cl-defun health-chart-svg-timeseries (ms &rest props &key width height title &allow-other-keys)
  "SVG time series of one marker in MS with shaded bands.
WIDTH, HEIGHT and TITLE are among PROPS, as for the text renderer."
  (health-chart-svg--series-chart (apply #'health-chart-model-series ms props)
                                  (or width health-chart-svg-width)
                                  (or height health-chart-svg-height) title))

(cl-defun health-chart-svg-compare (ms &rest props &key width height title &allow-other-keys)
  "SVG overlay of one marker in MS for every person.
WIDTH, HEIGHT and TITLE are among PROPS, as for the text renderer."
  (health-chart-svg--series-chart (apply #'health-chart-model-series ms :compare t props)
                                  (or width health-chart-svg-width)
                                  (or height health-chart-svg-height) title))

(cl-defun health-chart-svg-panel (ms &rest props &key width columns title &allow-other-keys)
  "SVG small multiples: one compact series per marker of MS.
WIDTH, COLUMNS and TITLE are among PROPS."
  (let* ((models (apply #'health-chart-model-panel ms props))
         (width (or width health-chart-svg-width))
         (columns (max 1 (or columns (max 1 (/ width 300)))))
         (cell-w (/ width (float columns)))
         (cell-h 150)
         (rows (ceiling (length models) (float columns)))
         (height (+ 40 (* rows cell-h))))
    (when models
      (let ((svg (health-chart-svg--canvas
                  width height (or title (format "Panel · %s" (or (plist-get (car models) :person) "all"))))))
        (cl-loop for model in models for i from 0
                 for cx = (* cell-w (mod i columns))
                 for cy = (+ 40 (* cell-h (/ i columns)))
                 for latest = (plist-get model :latest)
                 for status = (health-chart-status latest)
                 do (health-chart-svg--text svg (plist-get model :label) (+ cx 12) (+ cy 14) :weight "bold")
                 do (health-chart-svg--text
                     svg (format "%s  %s" (health-chart-fmt-value latest) (health-chart-status-label status))
                     (- (+ cx cell-w) 10) (+ cy 14) :anchor "end"
                     :color (health-chart-svg--c 'secondary) :size (1- health-chart-svg-font-size))
                 do (health-chart-svg--series-box svg model cx (+ cy 24) cell-w (- cell-h 32) t))
        (health-chart-svg--string svg)))))

;; -----------------------------------------------------------------------
;; Table, range bars, heatmap, delta, sparkline
;; -----------------------------------------------------------------------

(defun health-chart-svg--spark (svg values x y w h color)
  "Draw VALUES as a sparkline polyline into SVG's X,Y,W,H box in COLOR."
  (when values
    (let* ((lo (apply #'min values)) (hi (apply #'max values))
           (n (length values))
           (pts (cl-loop for v in values for i from 0
                         collect (cons (health-chart-svg--n (+ x (if (= n 1) (/ w 2.0) (* w (/ i (float (1- n)))))))
                                       (health-chart-svg--n (+ y (if (= lo hi) (/ h 2.0)
                                                                   (* h (- 1 (/ (- v lo) (float (- hi lo))))))))))))
      (if (cdr pts)
          (svg-polyline svg pts :fill "none" :stroke color :stroke-width 2
                        :stroke-linejoin "round" :stroke-linecap "round")
        (svg-circle svg (caar pts) (cdar pts) 2.5 :fill color))
      (let ((end (car (last pts))))
        (svg-circle svg (car end) (cdr end) 3 :fill color)))))

(cl-defun health-chart-svg-table (ms &rest props &key width title &allow-other-keys)
  "SVG sparkline table of MS: marker | latest | trend | flag | reference.
WIDTH and TITLE are among PROPS."
  (let* ((rows (apply #'health-chart-model-table ms props))
         (width (or width health-chart-svg-width))
         (row-h 26) (top 58)
         (height (+ top (* row-h (length rows)) 10))
         (cols (list 12 (* width 0.31) (* width 0.34) (* width 0.55) (* width 0.75))))
    (when rows
      (let ((svg (health-chart-svg--canvas
                  width height (or title (format "Biomarkers · %s" (or (plist-get (car rows) :person) "all"))))))
        (cl-loop for label in '("Marker" "Latest" "Trend" "Flag" "Reference") for x in cols
                 do (health-chart-svg--text svg label (if (equal label "Latest") (- x 8) x) (- top 10)
                                            :anchor (if (equal label "Latest") "end" "start")
                                            :color (health-chart-svg--c 'muted)))
        (cl-loop
         for r in rows for i from 0
         for y = (+ top (* i row-h))
         for status = (plist-get r :status)
         for latest = (plist-get r :latest)
         do (svg-line svg 12 y (- width 12) y :stroke (health-chart-svg--c 'grid))
         do (let ((g (health-chart-svg--group
                      svg (format "%s: %s on %s, %s; reference %s" (plist-get r :label)
                                  (health-chart-fmt-value latest) (plist-get latest :date)
                                  (health-chart-status-label status) (plist-get r :ref)))))
              (health-chart-svg--text g (plist-get r :label) (nth 0 cols) (+ y 17))
              (health-chart-svg--text g (health-chart-fmt-value latest) (- (nth 1 cols) 8) (+ y 17)
                                      :anchor "end" :weight "bold")
              (health-chart-svg--spark g (plist-get r :values) (nth 2 cols) (+ y 6)
                                       (- (nth 3 cols) (nth 2 cols) 24) (- row-h 12)
                                       (health-chart-svg--c 'normal))
              (svg-circle g (+ (nth 3 cols) 5) (+ y 13) 5 :fill (health-chart-svg--status-color status))
              (health-chart-svg--text g (health-chart-status-label status) (+ (nth 3 cols) 15) (+ y 17))
              (health-chart-svg--text g (concat (plist-get r :ref)
                                                (if (string-empty-p (plist-get r :opt)) ""
                                                  (format " (opt %s)" (plist-get r :opt))))
                                      (nth 4 cols) (+ y 17) :color (health-chart-svg--c 'secondary))))
        (health-chart-svg--string svg)))))

(cl-defun health-chart-svg-bullet (ms &rest props &key width title &allow-other-keys)
  "SVG range bars: each marker's latest value in MS against its ranges.
WIDTH and TITLE are among PROPS."
  (let* ((rows (apply #'health-chart-model-bullet ms props))
         (width (or width health-chart-svg-width))
         (row-h 30) (top 44)
         (height (+ top (* row-h (length rows)) 24))
         (tx 120) (tw (max 40 (- width tx 205))))
    (when rows
      (let ((svg (health-chart-svg--canvas
                  width height (or title (format "Latest vs range · %s"
                                                 (or (plist-get (plist-get (car rows) :latest) :person)
                                                     "all"))))))
        (cl-loop
         for r in rows for i from 0
         for y = (+ top (* i row-h))
         for (lo . hi) = (plist-get r :domain)
         for sx = (lambda (v) (health-chart-svg--n (+ tx (* tw (/ (- (max lo (min hi v)) lo)
                                                                  (float (- hi lo)))))))
         for status = (plist-get r :status)
         do (let ((g (health-chart-svg--group
                      svg (format "%s: %s, %s%s%s" (plist-get r :label)
                                  (health-chart-fmt-value (plist-get r :latest))
                                  (health-chart-status-label status)
                                  (if-let* ((ref (plist-get r :ref)))
                                      (format "; reference %s" (health-chart-fmt-range (car ref) (cdr ref))) "")
                                  (if-let* ((opt (plist-get r :opt)))
                                      (format "; optimal %s" (health-chart-fmt-range (car opt) (cdr opt))) "")))))
              (health-chart-svg--text g (plist-get r :label) 12 (+ y 18))
              (svg-rectangle g tx (+ y 8) tw 14 :fill (health-chart-svg--c 'grid) :rx 2)
              (dolist (band (list (cons (plist-get r :ref) (cons (health-chart-svg--c 'ref-band) 1))
                                  (cons (plist-get r :opt) (cons (health-chart-svg--c 'opt-band) 0.35))))
                (when-let* ((b (car band)))
                  (let ((x0 (funcall sx (or (car b) lo))) (x1 (funcall sx (or (cdr b) hi))))
                    (when (> x1 x0)
                      (svg-rectangle g x0 (+ y 8) (health-chart-svg--n (- x1 x0)) 14
                                     :fill (cadr band) :fill-opacity (cddr band))))))
              (let ((vx (funcall sx (plist-get r :value))))
                (svg-rectangle g (- vx 2) (+ y 3) 4 24 :rx 2
                               :fill (health-chart-svg--status-color status)
                               :stroke (health-chart-svg--c 'surface) :stroke-width 1))
              (health-chart-svg--text g (health-chart-fmt-value (plist-get r :latest))
                                      (+ tx tw 82) (+ y 19) :anchor "end" :weight "bold")
              (health-chart-svg--text g (health-chart-status-label status) (+ tx tw 92) (+ y 19)
                                      :color (health-chart-svg--c 'secondary))))
        (health-chart-svg--text svg (string-join
                                     (delq nil (list "bar = latest"
                                                     (when (seq-some (lambda (r) (plist-get r :opt)) rows)
                                                       "green = optimal")
                                                     (when (seq-some (lambda (r) (plist-get r :ref)) rows)
                                                       "gray = reference")))
                                     "   ")
                                12 (- height 8) :color (health-chart-svg--c 'muted)
                                :size (1- health-chart-svg-font-size))
        (health-chart-svg--string svg)))))

(cl-defun health-chart-svg-heatmap (ms &rest props &key width title &allow-other-keys)
  "SVG out-of-range heatmap of MS: markers by draw dates, cells by status.
WIDTH and TITLE are among PROPS."
  (let* ((model (apply #'health-chart-model-heatmap ms props))
         (rows (plist-get model :rows))
         (dates (plist-get model :dates))
         (width (or width health-chart-svg-width))
         (lx 120) (top 64) (row-h 24)
         (cell-w (max 14 (min 48 (/ (- width lx 60) (float (max 1 (length dates)))))))
         (height (+ top (* row-h (length rows)) 30)))
    (when rows
      (let ((svg (health-chart-svg--canvas
                  width height (or title (format "Out of range · %s" (or (plist-get model :person) "all"))))))
        (cl-loop for d in dates for j from 0
                 for cx = (+ lx (* j cell-w) (/ cell-w 2))
                 do (health-chart-svg--text svg (health-chart-format-date d "%y") cx (- top 20)
                                            :anchor "middle" :color (health-chart-svg--c 'muted)
                                            :size (1- health-chart-svg-font-size))
                 do (health-chart-svg--text svg (health-chart-format-date d "%b") cx (- top 6)
                                            :anchor "middle" :color (health-chart-svg--c 'muted)
                                            :size (1- health-chart-svg-font-size)))
        (cl-loop
         for r in rows for i from 0
         for y = (+ top (* i row-h))
         do (health-chart-svg--text svg (plist-get r :label) 12 (+ y 16))
         do (cl-loop
             for c in (plist-get r :cells) for d in dates for j from 0
             for x = (+ lx (* j cell-w))
             do (if (null c)
                    (svg-rectangle svg (+ x 1) (+ y 1) (- cell-w 2) (- row-h 2) :rx 3
                                   :fill "none" :stroke (health-chart-svg--c 'grid))
                  (let* ((s (health-chart-status c))
                         (g (health-chart-svg--group
                             svg (format "%s %s: %s (%s)" (plist-get r :label) d
                                         (health-chart-fmt-value c) (health-chart-status-label s)))))
                    (svg-rectangle g (+ x 1) (+ y 1) (- cell-w 2) (- row-h 2) :rx 3
                                   :fill (health-chart-svg--status-color s))
                    (health-chart-svg--text g (health-chart-status-glyph s) (+ x (/ cell-w 2)) (+ y 16)
                                            :anchor "middle"
                                            :color (if (memq s '(suboptimal)) "#0b0b0b" "#ffffff")))))
         do (health-chart-svg--text svg (format "%d/%d" (plist-get r :out)
                                                (seq-count #'identity (plist-get r :cells)))
                                    (+ lx (* (length dates) cell-w) 10) (+ y 16)
                                    :color (health-chart-svg--c 'secondary)))
        (health-chart-svg--text svg (mapconcat #'health-chart-status-label
                                               '(optimal normal suboptimal high low) "   ")
                                12 (- height 10) :color (health-chart-svg--c 'muted)
                                :size (1- health-chart-svg-font-size))
        (health-chart-svg--string svg)))))

(cl-defun health-chart-svg-delta (ms &rest props &key width title &allow-other-keys)
  "SVG diverging percent-change bars between two draws in MS.
WIDTH and TITLE are among PROPS."
  (let* ((model (apply #'health-chart-model-delta ms props))
         (rows (plist-get model :rows))
         (width (or width health-chart-svg-width))
         (row-h 26) (top 44)
         (height (+ top (* row-h (length rows)) 16))
         (lx 120) (rx 240)
         (half (max 20 (/ (- width lx rx) 2.0)))
         (mid (+ lx half))
         (scale (apply #'max 1e-9 (mapcar (lambda (r) (abs (or (plist-get r :pct) 0))) rows))))
    (when rows
      (let ((svg (health-chart-svg--canvas
                  width height (or title (format "Change %s → %s · %s" (plist-get model :from)
                                                 (plist-get model :to) (or (plist-get model :person) "all"))))))
        (svg-line svg mid (- top 4) mid (+ top (* row-h (length rows))) :stroke (health-chart-svg--c 'axis))
        (cl-loop
         for r in rows for i from 0
         for y = (+ top (* i row-h))
         for pct = (or (plist-get r :pct) 0)
         for len = (* half (/ (abs pct) scale))
         for verdict = (plist-get r :verdict)
         for color = (health-chart-svg--c (pcase verdict ('improved 'good) ('worsened 'critical) (_ 'muted)))
         do (let ((g (health-chart-svg--group
                      svg (format "%s: %s → %s %s (%s) %s" (plist-get r :label)
                                  (health-chart-fmt (plist-get r :before)) (health-chart-fmt (plist-get r :after))
                                  (or (plist-get r :unit) "")
                                  (if (plist-get r :pct) (format "%+.1f%%" pct) "n/a")
                                  (or verdict "")))))
              (health-chart-svg--text g (plist-get r :label) 12 (+ y 17))
              (svg-rectangle g (health-chart-svg--n (if (< pct 0) (- mid len) mid)) (+ y 6)
                             (health-chart-svg--n (max 1 len)) 14 :rx 2 :fill color)
              (health-chart-svg--text g (format "%s → %s  %s" (health-chart-fmt (plist-get r :before))
                                                (health-chart-fmt (plist-get r :after))
                                                (if (plist-get r :pct) (format "%+.1f%%" pct) "n/a"))
                                      (- width rx -10) (+ y 17) :color (health-chart-svg--c 'secondary))
              (health-chart-svg--text g (format "%s" (or verdict "")) (- width 12) (+ y 17)
                                      :anchor "end" :color (health-chart-svg--c 'ink))))
        (health-chart-svg--string svg)))))

(cl-defun health-chart-svg-sparkline (values &key width height &allow-other-keys)
  "SVG sparkline of numeric VALUES, WIDTH x HEIGHT pixels (default 120x24)."
  (let ((values (seq-filter #'numberp (append values nil)))
        (width (or width 120)) (height (or height 24)))
    (when values
      (let ((svg (svg-create width height)))
        (health-chart-svg--spark svg values 3 3 (- width 6) (- height 6) (health-chart-svg--c 'normal))
        (health-chart-svg--string svg)))))

(provide 'health-chart-svg)
;;; health-chart-svg.el ends here
