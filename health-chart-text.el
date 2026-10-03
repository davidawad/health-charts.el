;;; health-chart-text.el --- Unicode text renderers for health-chart -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Every chart kind as propertized unicode text.  Deterministic: the
;; same data and props give the same string, so the text backend is what
;; tests (and agents reading a chart) rely on.  Bands are glyphs, not
;; just colors -- ░ reference, ▒ optimal -- and every status carries a
;; glyph and a word, so nothing depends on color alone.
;;
;; Rows of the sparkline table carry the text properties
;; `health-chart-marker' and `health-chart-person', which the dashboard
;; uses to open a marker's time series.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'health-chart-core)
(require 'health-chart-model)

(defun health-chart-text--p (s face)
  "S with FACE (unchanged when FACE is nil)."
  (if face (propertize s 'face face) s))

;; -----------------------------------------------------------------------
;; The time-series grid: shared by timeseries, compare and panel
;; -----------------------------------------------------------------------

(defun health-chart-text--y-row (v lo hi height)
  "Row (0 = top) value V falls in on a LO..HI scale of HEIGHT rows."
  (max 0 (min (1- height)
              (floor (* (/ (- hi v) (float (- hi lo))) height)))))

(defun health-chart-text--x-col (day d0 d1 width)
  "Column DAY falls in across WIDTH columns spanning days D0..D1."
  (if (= d0 d1) (/ width 2)
    (round (* (/ (- day d0) (float (- d1 d0))) (1- width)))))

(defun health-chart-text--in-band-p (v band)
  "Non-nil when V lies inside BAND, a (LO . HI) cons with nil bounds open."
  (and band (or (null (car band)) (>= v (car band)))
       (or (null (cdr band)) (<= v (cdr band)))))

(defun health-chart-text--y-labels (lo hi height count)
  "Alist (ROW . LABEL) of about COUNT round values on a LO..HI axis.
The axis is HEIGHT rows tall.
Each label sits on the row its value falls in; one label per row, and
no label text twice."
  (let (out)
    (dolist (v (health-chart-nice-ticks lo hi count))
      (let ((row (health-chart-text--y-row v lo hi height))
            (label (health-chart-fmt v)))
        (unless (or (assq row out) (rassoc label out))
          (push (cons row label) out))))
    (nreverse out)))

(defun health-chart-text--grid (model width height &optional compact)
  "Lines of MODEL's series chart: WIDTH columns overall, HEIGHT plot rows.
COMPACT drops the date axis labels to the first and last date."
  (pcase-let* ((`(,lo . ,hi) (plist-get model :y-range))
               (`(,d0 . ,d1) (plist-get model :x-range))
               (strings (health-chart-text--y-labels lo hi height (if compact 3 4)))
               (lw (1+ (apply #'max (mapcar (lambda (s) (string-width (cdr s))) strings))))
               (w (max 4 (- width lw 1)))
               (grid (make-vector height nil))
               (ref (plist-get model :ref))
               (opt (plist-get model :opt))
               (unit (/ (- hi lo) (float height))))
    ;; background: bands
    (dotimes (r height)
      (let* ((center (- hi (* (+ r 0.5) unit)))
             (cell (cond ((health-chart-text--in-band-p center opt)
                          (cons health-chart-glyph-optimal-band 'health-chart-optimal-band))
                         ((health-chart-text--in-band-p center ref)
                          (cons health-chart-glyph-ref-band 'health-chart-ref-band))
                         (t (cons ?\s nil)))))
        (aset grid r (make-vector w cell))))
    ;; series: connectors first, then points on top
    (cl-loop
     for line in (plist-get model :lines) for i from 0
     for compare = (plist-get model :compare)
     for glyph = (if compare (nth (mod i (length health-chart-series-glyphs))
                                  health-chart-series-glyphs)
                   (car health-chart-series-glyphs))
     for face = (if compare (nth (mod i (length health-chart-series-faces))
                                 health-chart-series-faces)
                  'health-chart-accent)
     for cells = (mapcar (lambda (p)
                           (list (health-chart-text--x-col (nth 0 p) d0 d1 w)
                                 (health-chart-text--y-row (nth 1 p) lo hi height)
                                 (nth 2 p)))
                         (plist-get line :points))
     do (cl-loop for (a b) on cells while b
                 for (c1 r1) = a for (c2 r2) = b
                 do (cl-loop for c from (1+ c1) below c2
                             for r = (round (+ r1 (* (- r2 r1) (/ (- c c1) (float (- c2 c1))))))
                             do (aset (aref grid r) c (cons health-chart-glyph-connector face))))
     do (dolist (cell cells)
          (aset (aref grid (nth 1 cell)) (nth 0 cell)
                (cons glyph (if compare face
                              (health-chart-status-face (health-chart-status (nth 2 cell))))))))
    (append
     (cl-loop for r from 0 below height
              for label = (cdr (assq r strings))
              collect (string-trim-right
                       (concat (health-chart-text--p (health-chart-pad label (1- lw) t) 'health-chart-dim)
                               (health-chart-text--p (if label " ┤" " │") 'health-chart-dim)
                               (mapconcat (lambda (cell)
                                            (health-chart-text--p (string (car cell)) (cdr cell)))
                                          (aref grid r) ""))))
     (list (health-chart-text--p (concat (make-string lw ?\s) "└" (make-string w ?─))
                                 'health-chart-dim)
           (health-chart-text--p
            (concat (make-string (1+ lw) ?\s)
                    (health-chart-text--date-axis model w compact))
            'health-chart-dim)))))

(defun health-chart-text--date-axis (model width compact)
  "Date labels under a series plot of MODEL, WIDTH columns wide.
COMPACT shows only the first and last dates, abbreviated."
  (pcase-let* ((`(,d0 . ,d1) (plist-get model :x-range))
               (fmt (if compact "%y-%m" health-chart-date-format))
               (first (health-chart-format-date (health-chart-days-date d0) fmt))
               (last (health-chart-format-date (health-chart-days-date d1) fmt))
               (axis (make-string width ?\s)))
    (cl-flet ((place (s col)
                (let ((col (max 0 (min col (- width (length s))))))
                  (when (<= (+ col (length s)) width)
                    (setq axis (concat (substring axis 0 col) s
                                       (substring axis (+ col (length s)))))))))
      (if (= d0 d1)
          (place first (- (/ width 2) (/ (length first) 2)))
        (place first 0)
        (place last (- width (length last)))
        (when (and (not compact) (>= width (+ (* 3 (length first)) 6)))
          (let* ((mid (health-chart-format-date (health-chart-days-date (/ (+ d0 d1) 2)) fmt)))
            (place mid (- (/ width 2) (/ (length mid) 2)))))))
    (string-trim-right axis)))

(defun health-chart-text--legend (model)
  "Legend line naming MODEL's glyphs and bands."
  (let* ((ref (plist-get model :ref)) (opt (plist-get model :opt))
         (parts
          (append
           (if (plist-get model :compare)
               (cl-loop for line in (plist-get model :lines) for i from 0
                        collect (health-chart-text--p
                                 (format "%c %s" (nth (mod i (length health-chart-series-glyphs))
                                                      health-chart-series-glyphs)
                                         (or (plist-get line :name) "?"))
                                 (nth (mod i (length health-chart-series-faces))
                                      health-chart-series-faces)))
             (list (format "%c value" (car health-chart-series-glyphs))))
           (when opt (list (health-chart-text--p
                            (format "%c optimal %s" health-chart-glyph-optimal-band
                                    (health-chart-fmt-range (car opt) (cdr opt)))
                            'health-chart-optimal-band)))
           (when ref (list (health-chart-text--p
                            (format "%c reference %s" health-chart-glyph-ref-band
                                    (health-chart-fmt-range (car ref) (cdr ref)))
                            'health-chart-ref-band))))))
    (string-join parts "   ")))

(defun health-chart-text--series-title (model)
  "Header line of a series MODEL: marker, person, unit, latest value."
  (let* ((latest (plist-get model :latest))
         (status (health-chart-status latest)))
    (concat (health-chart-text--p (plist-get model :label) 'health-chart-header)
            (health-chart-text--p
             (concat (if (plist-get model :person) (format " · %s" (plist-get model :person)) "")
                     (if (plist-get model :unit) (format " · %s" (plist-get model :unit)) ""))
             'health-chart-dim)
            (if (plist-get model :compare) ""
              (concat "   latest "
                      (health-chart-text--p (health-chart-fmt-value latest) 'health-chart-accent)
                      (health-chart-text--p (format " (%s) " (health-chart-format-date
                                                              (plist-get latest :date)))
                                            'health-chart-dim)
                      (health-chart-text--p (health-chart-status-label status)
                                            (health-chart-status-face status)))))))

(defun health-chart-text--series-chart (model width height title)
  "Title, grid and legend of series MODEL, every line at most WIDTH wide.
HEIGHT is the plot rows; TITLE replaces the derived title when non-nil."
  (let ((width (or width health-chart-width)))
    (mapconcat (lambda (line) (truncate-string-to-width line width nil nil "…"))
               (append (list (if title (health-chart-text--p title 'health-chart-header)
                               (health-chart-text--series-title model)))
                       (health-chart-text--grid model width (or height health-chart-height))
                       (list (health-chart-text--legend model)))
               "\n")))

(cl-defun health-chart-text-timeseries (ms &rest props &key width height title &allow-other-keys)
  "Text time series of one marker in MS with shaded bands.
PROPS: :marker :person :ref :optimal, and WIDTH, HEIGHT, TITLE."
  (when-let* ((model (apply #'health-chart-model-series ms props)))
    (health-chart-text--series-chart model width height title)))

(cl-defun health-chart-text-compare (ms &rest props &key width height title &allow-other-keys)
  "Text overlay of one marker in MS for every person, one glyph each.
PROPS: :marker :ref :optimal, and WIDTH, HEIGHT, TITLE."
  (when-let* ((model (apply #'health-chart-model-series ms :compare t props)))
    (health-chart-text--series-chart model width height title)))

;; -----------------------------------------------------------------------
;; Panel: small multiples
;; -----------------------------------------------------------------------

(defun health-chart-text--panel-cell (model width height)
  "Lines of one small-multiple cell for MODEL, HEIGHT plot rows tall.
Each line is WIDTH columns wide."
  (let* ((latest (plist-get model :latest))
         (status (health-chart-status latest))
         (head (concat (health-chart-text--p (plist-get model :label) 'health-chart-header)
                       " "
                       (health-chart-text--p (health-chart-fmt-value latest) 'health-chart-accent)
                       " "
                       (health-chart-text--p (health-chart-status-label status)
                                             (health-chart-status-face status)))))
    (mapcar (lambda (line) (health-chart-pad line width))
            (cons head (health-chart-text--grid model width height t)))))

(cl-defun health-chart-text-panel (ms &rest props &key width height columns title &allow-other-keys)
  "Small multiples: a compact time series per marker of MS, in a grid.
PROPS: :person :marker (a list limits markers) :ref :optimal, WIDTH
\(overall), HEIGHT (rows per cell, default 4), COLUMNS and TITLE."
  (let* ((models (apply #'health-chart-model-panel ms props))
         (width (or width health-chart-width))
         (gap 3)
         (columns (max 1 (or columns (max 1 (/ (+ width gap) 34)))))
         (cell-w (max 16 (/ (- width (* gap (1- columns))) columns)))
         (cells (mapcar (lambda (m) (health-chart-text--panel-cell m cell-w (or height 4)))
                        models))
         (blank (make-string cell-w ?\s))
         rows)
    (when models
      (while cells
        (let* ((group (seq-take cells columns))
               (n (apply #'max (mapcar #'length group))))
          (setq cells (seq-drop cells columns))
          (push (string-join
                 (cl-loop for i from 0 below n
                          collect (string-trim-right
                                   (mapconcat (lambda (cell) (or (nth i cell) blank))
                                              group (make-string gap ?\s))))
                 "\n")
                rows)))
      (concat (health-chart-text--p
               (or title (format "Panel · %s" (or (plist-get (car models) :person) "all")))
               'health-chart-header)
              "\n\n"
              (string-join (nreverse rows) "\n\n")))))

;; -----------------------------------------------------------------------
;; Sparklines and the sparkline table
;; -----------------------------------------------------------------------

(cl-defun health-chart-text-sparkline (values &key width face &allow-other-keys)
  "One-row eighth-block sparkline of numeric VALUES, at most WIDTH wide.
FACE defaults to `health-chart-accent'.  Nil when there are no values."
  (let* ((values (seq-filter #'numberp (append values nil)))
         (values (health-chart-model-resample values (or width (max 1 (length values))))))
    (when values
      (let ((lo (apply #'min values)) (hi (apply #'max values)))
        (health-chart-text--p
         (mapconcat (lambda (v)
                      (string (aref health-chart-blocks
                                    (if (= lo hi) 4
                                      (1+ (round (* 7 (/ (- v lo) (float (- hi lo))))))))))
                    values "")
         (or face 'health-chart-accent))))))

(cl-defun health-chart-text-table (ms &rest props &key title &allow-other-keys)
  "Sparkline table of MS: marker | latest | trend | flag | reference.
Each row carries `health-chart-marker' and `health-chart-person' text
properties.  PROPS: :person :marker :sparkline-width and TITLE."
  (let* ((rows (apply #'health-chart-model-table ms props))
         (spark-w (or (plist-get props :sparkline-width) health-chart-sparkline-width))
         (label-w (max 6 (apply #'max 0 (mapcar (lambda (r) (string-width (plist-get r :label))) rows))))
         (value-w (max 6 (apply #'max 0 (mapcar (lambda (r) (string-width (health-chart-fmt-value
                                                                          (plist-get r :latest))))
                                              rows))))
         (date-w 10)
         (flag-w 12))
    (when rows
      (string-join
       (append
        (list (health-chart-text--p (or title (format "Biomarkers · %s" (or (plist-get (car rows) :person) "all")))
                                    'health-chart-header)
              (health-chart-text--p
               (string-trim-right
                (concat (health-chart-pad "Marker" label-w) "  "
                        (health-chart-pad "Latest" value-w t) "  "
                        (health-chart-pad "Date" date-w) "  "
                        (health-chart-pad "Trend" spark-w) "  "
                        (health-chart-pad "Flag" flag-w) "  Reference"))
               'health-chart-dim))
        (mapcar
         (lambda (r)
           (let ((status (plist-get r :status))
                 (latest (plist-get r :latest)))
             (propertize
              (string-trim-right
               (concat (health-chart-pad (plist-get r :label) label-w) "  "
                       (health-chart-text--p (health-chart-pad (health-chart-fmt-value latest) value-w t)
                                             'health-chart-accent)
                       "  "
                       (health-chart-text--p (health-chart-pad (plist-get latest :date) date-w)
                                             'health-chart-dim)
                       "  "
                       (health-chart-pad (health-chart-text-sparkline (plist-get r :values) :width spark-w)
                                         spark-w)
                       "  "
                       (health-chart-text--p (health-chart-pad (health-chart-status-label status) flag-w)
                                             (health-chart-status-face status))
                       "  "
                       (health-chart-text--p
                        (string-trim (concat (plist-get r :ref)
                                             (if (string-empty-p (plist-get r :opt)) ""
                                               (format " (opt %s)" (plist-get r :opt)))))
                        'health-chart-dim)))
              'health-chart-marker (plist-get r :marker)
              'health-chart-person (plist-get latest :person))))
         rows))
       "\n"))))

;; -----------------------------------------------------------------------
;; Range bars (bullet chart)
;; -----------------------------------------------------------------------

(defun health-chart-text--track (row width)
  "The track of range-bar ROW with its value marker, WIDTH cells wide."
  (pcase-let* ((`(,lo . ,hi) (plist-get row :domain))
               (step (/ (- hi lo) (float width)))
               (col (max 0 (min (1- width) (floor (/ (- (plist-get row :value) lo) step))))))
    (mapconcat
     (lambda (c)
       (let ((center (+ lo (* (+ c 0.5) step))))
         (cond
          ((= c col) (health-chart-text--p (string health-chart-glyph-marker)
                                           (health-chart-status-face (plist-get row :status))))
          ((health-chart-text--in-band-p center (plist-get row :opt))
           (health-chart-text--p (string health-chart-glyph-optimal-band) 'health-chart-optimal-band))
          ((health-chart-text--in-band-p center (plist-get row :ref))
           (health-chart-text--p (string health-chart-glyph-ref-band) 'health-chart-ref-band))
          (t (health-chart-text--p "─" 'health-chart-dim)))))
     (number-sequence 0 (1- width)) "")))

(cl-defun health-chart-text-bullet (ms &rest props &key width title &allow-other-keys)
  "Range bars: where each marker's latest value in MS sits in its ranges.
PROPS: :person :marker :ref :optimal, WIDTH and TITLE."
  (let* ((rows (apply #'health-chart-model-bullet ms props))
         (label-w (max 6 (apply #'max 0 (mapcar (lambda (r) (string-width (plist-get r :label))) rows))))
         (value-w (max 6 (apply #'max 0 (mapcar (lambda (r) (string-width (health-chart-fmt-value
                                                                          (plist-get r :latest))))
                                              rows))))
         (track-w (max 10 (- (or width health-chart-width) label-w value-w 18))))
    (when rows
      (string-join
       (append
        (list (health-chart-text--p (or title (format "Latest vs range · %s"
                                                      (or (plist-get (plist-get (car rows) :latest) :person)
                                                          "all")))
                                    'health-chart-header))
        (mapcar (lambda (r)
                  (propertize
                   (concat (health-chart-pad (plist-get r :label) label-w) "  "
                           (health-chart-text--track r track-w) "  "
                           (health-chart-text--p (health-chart-pad (health-chart-fmt-value (plist-get r :latest))
                                                                   value-w t)
                                                 'health-chart-accent)
                           "  "
                           (health-chart-text--p (health-chart-status-label (plist-get r :status))
                                                 (health-chart-status-face (plist-get r :status))))
                   'health-chart-marker (plist-get r :marker)
                   'health-chart-person (plist-get (plist-get r :latest) :person)))
                rows)
        (list (health-chart-text--p
               (string-join
                (delq nil (list (format "%c latest" health-chart-glyph-marker)
                                (when (seq-some (lambda (r) (plist-get r :opt)) rows)
                                  (format "%c optimal" health-chart-glyph-optimal-band))
                                (when (seq-some (lambda (r) (plist-get r :ref)) rows)
                                  (format "%c reference" health-chart-glyph-ref-band))
                                "─ outside"))
                "   ")
               'health-chart-dim)))
       "\n"))))

;; -----------------------------------------------------------------------
;; Out-of-range heatmap
;; -----------------------------------------------------------------------

(cl-defun health-chart-text-heatmap (ms &rest props &key title &allow-other-keys)
  "Markers by draw dates for MS, each cell the draw's status glyph.
PROPS: :person :marker and TITLE."
  (let* ((model (apply #'health-chart-model-heatmap ms props))
         (rows (plist-get model :rows))
         (dates (plist-get model :dates))
         (label-w (max 6 (apply #'max 0 (mapcar (lambda (r) (string-width (plist-get r :label))) rows))))
         (pad (make-string (+ label-w 1) ?\s)))
    (when rows
      (string-join
       (append
        (list (health-chart-text--p (or title (format "Out of range · %s" (or (plist-get model :person) "all")))
                                    'health-chart-header)
              (health-chart-text--p
               (concat pad (mapconcat (lambda (d) (health-chart-format-date d " %y")) dates ""))
               'health-chart-dim)
              (health-chart-text--p
               (concat pad (mapconcat (lambda (d) (health-chart-format-date d " %m")) dates "")
                       "  out")
               'health-chart-dim))
        (mapcar
         (lambda (r)
           (propertize
            (concat (health-chart-pad (plist-get r :label) label-w) " "
                    (mapconcat (lambda (c)
                                 (if (null c) (health-chart-text--p "  ·" 'health-chart-dim)
                                   (let ((s (health-chart-status c)))
                                     (concat "  " (health-chart-text--p (health-chart-status-glyph s)
                                                                        (health-chart-status-face s))))))
                               (plist-get r :cells) "")
                    (format "  %d/%d" (plist-get r :out)
                            (seq-count #'identity (plist-get r :cells))))
            'health-chart-marker (plist-get r :marker)
            'health-chart-person (plist-get model :person)))
         rows)
        (list (health-chart-text--p
               (concat (mapconcat (lambda (s) (health-chart-status-label s))
                                  '(optimal normal suboptimal high low) "  ")
                       "  · no draw")
               'health-chart-dim)))
       "\n"))))

;; -----------------------------------------------------------------------
;; Delta bars between two draws
;; -----------------------------------------------------------------------

(defun health-chart-text--verdict-face (verdict)
  "Face for change VERDICT."
  (pcase verdict ('improved 'health-chart-improved) ('worsened 'health-chart-worsened)
         (_ 'health-chart-dim)))

(cl-defun health-chart-text-delta (ms &rest props &key width title &allow-other-keys)
  "Diverging percent-change bars between two draws in MS.
PROPS: :person :from :to :marker, WIDTH and TITLE."
  (let* ((model (apply #'health-chart-model-delta ms props))
         (rows (plist-get model :rows))
         (label-w (max 6 (apply #'max 0 (mapcar (lambda (r) (string-width (plist-get r :label))) rows))))
         (vals (mapcar (lambda (r)
                         (format "%s → %s %s" (health-chart-fmt (plist-get r :before))
                                 (health-chart-fmt (plist-get r :after)) (or (plist-get r :unit) "")))
                       rows))
         (vals-w (apply #'max 0 (mapcar #'string-width vals)))
         (half (max 4 (/ (- (or width health-chart-width) label-w vals-w 25) 2)))
         (scale (apply #'max 1e-9 (mapcar (lambda (r) (abs (or (plist-get r :pct) 0))) rows))))
    (when rows
      (string-join
       (append
        (list (health-chart-text--p
               (or title (format "Change %s → %s · %s" (plist-get model :from) (plist-get model :to)
                                 (or (plist-get model :person) "all")))
               'health-chart-header))
        (cl-loop
         for r in rows for v in vals
         collect
         (let* ((pct (or (plist-get r :pct) 0))
                (n (min half (round (* half (/ (abs pct) scale)))))
                (n (if (and (zerop n) (not (zerop pct))) 1 n))
                (face (health-chart-text--verdict-face (plist-get r :verdict)))
                (bar (make-string n ?█))
                (left (if (< pct 0) (concat (make-string (- half n) ?\s) (health-chart-text--p bar face))
                        (make-string half ?\s)))
                (right (if (> pct 0) (concat (health-chart-text--p bar face) (make-string (- half n) ?\s))
                         (make-string half ?\s))))
           (propertize
            (string-trim-right
             (concat (health-chart-pad (plist-get r :label) label-w) "  "
                     (health-chart-pad v vals-w) "  "
                     left (health-chart-text--p "│" 'health-chart-dim) right "  "
                     (health-chart-pad (if (plist-get r :pct) (format "%+.1f%%" pct) "n/a") 7 t) "  "
                     (health-chart-text--p (format "%s" (or (plist-get r :verdict) "")) face)))
            'health-chart-marker (plist-get r :marker)
            'health-chart-person (plist-get model :person)))))
       "\n"))))

;; -----------------------------------------------------------------------
;; Indicators: scorecard, cohort panel, staleness
;; -----------------------------------------------------------------------

(defun health-chart-text--indicator-value (row)
  "ROW's value formatted, or \"n/a\" when missing."
  (if (numberp (plist-get row :value)) (health-chart-fmt (plist-get row :value)) "n/a"))

(defun health-chart-text--trend (row width)
  "ROW's sparkline, at most WIDTH wide, and trend word."
  (let ((spark (health-chart-text-sparkline (plist-get row :series) :width width))
        (verdict (plist-get row :trend)))
    (string-trim-right
     (concat (health-chart-pad spark width) " "
             (health-chart-text--p (health-chart-indicator-trend-label verdict (plist-get row :series))
                                   (health-chart-trend-face verdict))))))

(defun health-chart-text--indicator-row (row text)
  "TEXT carrying ROW's marker, person and indicator text properties."
  (propertize text
              'health-chart-marker (plist-get row :marker)
              'health-chart-person (plist-get row :person)
              'health-chart-indicator (plist-get row :id)))

(cl-defun health-chart-text-scorecard (values &rest props &key title &allow-other-keys)
  "Indicator scorecard of VALUES: indicator | value | unit | status | trend.
Rows carry `health-chart-marker', `health-chart-person' and
`health-chart-indicator' text properties.  PROPS: :sparkline-width and
TITLE."
  (let* ((rows (apply #'health-chart-model-scorecard values props))
         (spark-w (or (plist-get props :sparkline-width) health-chart-sparkline-width))
         (width-of (lambda (fn min) (max min (apply #'max 0 (mapcar (lambda (r) (string-width (funcall fn r)))
                                                                    rows)))))
         (label-w (funcall width-of (lambda (r) (plist-get r :label)) 9))
         (value-w (funcall width-of #'health-chart-text--indicator-value 5))
         (unit-w (funcall width-of (lambda (r) (or (plist-get r :unit) "")) 4))
         (status-w 12))
    (when rows
      (string-join
       (append
        (list (health-chart-text--p (or title (health-chart-model-indicator-title values "Indicators"))
                                    'health-chart-header)
              (health-chart-text--p
               (concat (health-chart-pad "Indicator" label-w) "  "
                       (health-chart-pad "Value" value-w t) "  "
                       (health-chart-pad "Unit" unit-w) "  "
                       (health-chart-pad "Status" status-w) "  Trend")
               'health-chart-dim))
        (mapcar
         (lambda (r)
           (let ((status (plist-get r :status)))
             (health-chart-text--indicator-row
              r (string-trim-right
                 (concat (health-chart-pad (plist-get r :label) label-w) "  "
                         (health-chart-text--p (health-chart-pad (health-chart-text--indicator-value r)
                                                                 value-w t)
                                               'health-chart-accent)
                         "  "
                         (health-chart-text--p (health-chart-pad (or (plist-get r :unit) "") unit-w)
                                               'health-chart-dim)
                         "  "
                         (health-chart-text--p (health-chart-pad (health-chart-status-label status) status-w)
                                               (health-chart-status-face status))
                         "  "
                         (health-chart-text--trend r spark-w))))))
         rows))
       "\n"))))

(defun health-chart-text--cohort-card (card width)
  "Lines of one cohort-panel CARD, each WIDTH columns wide."
  (let* ((status (plist-get card :status))
         (state (health-chart-text--p (health-chart-status-label status)
                                      (health-chart-status-face status)))
         (label-w (max 4 (- width (string-width state) 1)))
         (value (if (numberp (plist-get card :value))
                    (concat (health-chart-text--p
                             (string-trim (format "%s %s" (health-chart-text--indicator-value card)
                                                  (or (plist-get card :unit) "")))
                             'health-chart-accent)
                            (health-chart-text--p
                             (if (plist-get card :date) (format " · %s" (plist-get card :date)) "")
                             'health-chart-dim))
                  (health-chart-text--p "n/a · no draw" 'health-chart-dim))))
    (mapcar (lambda (line) (health-chart-pad line width))
            (list (concat (health-chart-text--p (health-chart-pad (plist-get card :label) label-w)
                                                'health-chart-header)
                          " " state)
                  value
                  (if (plist-get card :domain)
                      (health-chart-text--track card width)
                    (health-chart-text--p "no range to place it in" 'health-chart-dim))
                  (health-chart-text--trend card (min health-chart-sparkline-width
                                                      (max 4 (- width 13))))))))

(cl-defun health-chart-text-cohort (values &rest props &key width columns title &allow-other-keys)
  "Cohort panel of indicator VALUES: a card per indicator, in a grid.
A card shows the value, its status, a track placing it in its ranges
\(or bounds) and its trend.  PROPS: :ref :optimal, WIDTH (overall),
COLUMNS and TITLE."
  (let* ((cards (apply #'health-chart-model-cohort values props))
         (width (or width health-chart-width))
         (gap 3)
         (columns (max 1 (or columns (max 1 (/ (+ width gap) 34)))))
         (cell-w (max 20 (/ (- width (* gap (1- columns))) columns)))
         (blank (make-string cell-w ?\s))
         (cells (mapcar (lambda (c)
                          (mapcar (lambda (line) (health-chart-text--indicator-row c line))
                                  (health-chart-text--cohort-card c cell-w)))
                        cards))
         rows)
    (when cards
      (while cells
        (let ((group (seq-take cells columns)))
          (setq cells (seq-drop cells columns))
          (push (string-trim-right
                 (string-join
                  (cl-loop for i from 0 below (apply #'max (mapcar #'length group))
                           collect (string-trim-right
                                    (mapconcat (lambda (cell) (or (nth i cell) blank))
                                               group (make-string gap ?\s))))
                  "\n"))
                rows)))
      (concat (health-chart-text--p (or title (health-chart-model-indicator-title values "Cohort"))
                                    'health-chart-header)
              "\n\n"
              (string-join (nreverse rows) "\n\n")
              "\n\n"
              (health-chart-text--p
               (string-join
                (delq nil (list (format "%c value" health-chart-glyph-marker)
                                (when (seq-some (lambda (c) (plist-get c :opt)) cards)
                                  (format "%c optimal" health-chart-glyph-optimal-band))
                                (when (seq-some (lambda (c) (plist-get c :ref)) cards)
                                  (format "%c reference or bounds" health-chart-glyph-ref-band))
                                "─ outside"))
                "   ")
               'health-chart-dim)))))

(defun health-chart-text--age-bar (row model width)
  "ROW's days-since-draw bar on MODEL's scale, WIDTH cells wide."
  (let* ((scale (float (plist-get model :scale)))
         (days (plist-get row :days))
         (col (lambda (d) (min (1- width) (floor (* width (/ d scale))))))
         (due (funcall col (plist-get model :due)))
         (stale (funcall col (plist-get model :stale)))
         (face (health-chart-staleness-face (plist-get row :state))))
    (mapconcat
     (lambda (c)
       (cond
        ((and days (<= (* (+ c 0.5) (/ scale width)) days)) (health-chart-text--p "█" face))
        ((= c stale) (health-chart-text--p "│" 'health-chart-dim))
        ((= c due) (health-chart-text--p "┆" 'health-chart-dim))
        (t (health-chart-text--p "─" 'health-chart-dim))))
     (number-sequence 0 (1- width)) "")))

(cl-defun health-chart-text-staleness (values &rest props &key width title &allow-other-keys)
  "Days since each indicator in VALUES was drawn, against due and stale lines.
PROPS: :as-of :due-days :stale-days, WIDTH and TITLE."
  (let* ((model (apply #'health-chart-model-staleness values props))
         (rows (plist-get model :rows))
         (label-w (max 6 (apply #'max 0 (mapcar (lambda (r) (string-width (plist-get r :label))) rows))))
         (days-w (max 4 (apply #'max 0 (mapcar (lambda (r) (length (format "%s d" (or (plist-get r :days) "–"))))
                                               rows))))
         (bar-w (max 10 (- (or width health-chart-width) label-w days-w 10 22))))
    (when rows
      (string-join
       (append
        (list (health-chart-text--p
               (or title (format "%s · as of %s"
                                 (health-chart-model-indicator-title values "Days since draw")
                                 (plist-get model :as-of)))
               'health-chart-header))
        (mapcar
         (lambda (r)
           (health-chart-text--indicator-row
            r (concat (health-chart-pad (plist-get r :label) label-w) "  "
                      (health-chart-text--p (health-chart-pad (or (plist-get r :date) "no draw") 10)
                                            'health-chart-dim)
                      "  "
                      (health-chart-text--age-bar r model bar-w) "  "
                      (health-chart-text--p
                       (health-chart-pad (if (plist-get r :days) (format "%d d" (plist-get r :days)) "–")
                                         days-w t)
                       'health-chart-accent)
                      "  "
                      (health-chart-text--p (health-chart-staleness-label (plist-get r :state))
                                            (health-chart-staleness-face (plist-get r :state))))))
         rows)
        (list (health-chart-text--p
               (format "┆ due after %d d   │ stale after %d d   %s"
                       (plist-get model :due) (plist-get model :stale)
                       (mapconcat #'health-chart-staleness-label '(fresh due stale) "  "))
               'health-chart-dim)))
       "\n"))))

(provide 'health-chart-text)
;;; health-chart-text.el ends here
