;;; health-chart-eas.el --- health-chart's shapes and range logic on eas -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; The domain half of the eas engine for health-chart.  It registers,
;; through eas's public registries only:
;;
;;   adapters    biomarker (canonical measurements -> tidy rows) and
;;               indicator-values (canonical indicator values -> rows)
;;   transforms  status, reference-band, change, staleness and trend:
;;               the range and status logic, run inside the chart
;;               document.  Each calls the package's own rules
;;               (`health-chart-status', `health-chart-ranges',
;;               `health-chart-model--verdict', ...), so "high",
;;               "optimal" and "improved" have one definition.
;;   templates   templates/eas/ (health-timeseries, health-bullet, ...),
;;               added to `eas-template-directories'
;;
;; eas never refers to health-chart; dependencies point this way.  The
;; kinds-to-templates table and the render entry points are in
;; health-chart-eas-route.el.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'eas)
(require 'health-chart-core)
(require 'health-chart-kind)
(require 'health-chart-model)
(require 'health-chart-spec)
(require 'health-chart-spec-gallery)

;;; Rows

(defun health-chart-eas--num (value)
  "VALUE when it is a number, else nil (`:null' and missing are nil)."
  (and (numberp value) value))

(defun health-chart-eas--null (value)
  "VALUE, or `:null' when it is nil."
  (if (null value) :null value))

(defun health-chart-eas--put (row &rest pairs)
  "A copy of ROW with PAIRS (KEY VALUE ...) set; nil values become `:null'."
  (cl-loop for (key value) on pairs by #'cddr
           do (setq row (eas-plist-put row key (health-chart-eas--null value))))
  row)

(defun health-chart-eas--row-measurement (row)
  "ROW (a biomarker row) as a canonical measurement plist."
  (let ((flag (plist-get row :flag)))
    (list :person (and (stringp (plist-get row :person)) (plist-get row :person))
          :marker (plist-get row :marker) :label (plist-get row :label)
          :unit (and (stringp (plist-get row :unit)) (plist-get row :unit))
          :date (plist-get row :date) :value (health-chart-eas--num (plist-get row :value))
          :ref-low (health-chart-eas--num (plist-get row :ref_low))
          :ref-high (health-chart-eas--num (plist-get row :ref_high))
          :opt-low (health-chart-eas--num (plist-get row :opt_low))
          :opt-high (health-chart-eas--num (plist-get row :opt_high))
          :flag (and (stringp flag) (not (string-empty-p flag)) (intern flag)))))

(defun health-chart-eas--group-rows (rows key)
  "ROWS (a vector) grouped by KEY as ((VALUE . ROWS) ...), first appearance order."
  (let (groups)
    (seq-doseq (row rows)
      (let* ((k (plist-get row key))
             (cell (assoc k groups)))
        (if cell (setcdr cell (cons row (cdr cell)))
          (push (list k row) groups))))
    (mapcar (lambda (g) (cons (car g) (nreverse (cdr g)))) (nreverse groups))))

(defun health-chart-eas--sorted-by-date (rows)
  "ROWS (a list) oldest first."
  (seq-sort-by (lambda (r) (plist-get r :date)) #'string< rows))

;;; adapters

(defun health-chart-eas--measurement-row (m ms)
  "The tidy row of canonical measurement M; MS supplies marker labels."
  (let ((flag (plist-get m :flag)))
    (append
     (list :person (health-chart-eas--null (plist-get m :person))
           :marker (plist-get m :marker)
           :label (health-chart-marker-label-in (plist-get m :marker) ms)
           :unit (or (plist-get m :unit) "")
           :date (plist-get m :date) :value (plist-get m :value)
           :ref_low (health-chart-eas--null (plist-get m :ref-low))
           :ref_high (health-chart-eas--null (plist-get m :ref-high))
           :opt_low (health-chart-eas--null (plist-get m :opt-low))
           :opt_high (health-chart-eas--null (plist-get m :opt-high))
           :flag (if flag (format "%s" flag) :null)
           :category (health-chart-marker-category m))
     ;; the axis a dual chart draws this marker on, set by the caller
     (when (stringp (plist-get m :axis)) (list :axis (plist-get m :axis))))))

(defun health-chart-eas--invalid (err shape)
  "Signal eas SHAPE_INVALID for health-chart data error ERR of SHAPE."
  (let ((props (cddr err)))
    (eas-signal "SHAPE_INVALID" (format "%s" (cadr err))
                :index (plist-get props :index) :field (plist-get props :field)
                :shape shape)))

(defun health-chart-eas--convert-measurements (data)
  "Rows of measurements DATA, in any form the source normalizer takes.
See `health-chart-source-normalize-list'.  A JSON array, a list of plists
or alists, snake_case or kebab-case
members, or a biomarker/v1 envelope.  A draw with no ranges takes its
marker's.  An :axis member (\"left\" or \"right\", how a dual chart
assigns its two markers) rides along as the column axis."
  (let* ((raw (cond ((vectorp data) (append data nil))
                    ;; a biomarker/v1 envelope read from JSON as a plist
                    ((and (consp data) (keywordp (car data))) (plist-get data :measurements))
                    (t data)))
         (axes (and (listp raw)
                    (mapcar (lambda (m) (and (consp m) (keywordp (car m)) (plist-get m :axis)))
                            raw)))
         (ms (condition-case err
                 (health-chart-source-normalize-list raw)
               (health-chart-error (health-chart-eas--invalid err "biomarker")))))
    (condition-case err
        (health-chart--validate-measurements ms)
      (health-chart-invalid-data (health-chart-eas--invalid err "biomarker")))
    (let ((ms (health-chart-fill-ranges ms)))
      (eas-data-make
       (vconcat (cl-loop for m in ms for i from 0
                         collect (let ((axis (nth i axes)))
                                   (health-chart-eas--measurement-row
                                    (if (stringp axis) (plist-put (copy-sequence m) :axis axis) m)
                                    ms))))))))

(eas-register-adapter
 "biomarker"
 :doc "health-chart measurements as rows {person, marker, label, unit, date, value, ref_low, ref_high, opt_low, opt_high, flag, category}; plists, alists, JSON objects (snake_case or kebab-case) or a biomarker/v1 envelope; a draw with no ranges takes its marker's."
 :example (health-chart--example-measurements '("alex"))
 :convert #'health-chart-eas--convert-measurements)

(defun health-chart-eas--convert-indicators (data)
  "Rows of indicator values DATA, in any form the normalizer takes.
See `health-chart-indicator-normalize-values'."
  (let ((data (condition-case err
                  (health-chart-indicator-normalize-values data)
                (health-chart-error (health-chart-eas--invalid err "indicator-values")))))
    (condition-case err
        (health-chart-indicator-validate-values data)
      (health-chart-error (health-chart-eas--invalid err "indicator-values")))
    (eas-data-make
     (vconcat
      (mapcar (lambda (v)
                (list :id (plist-get v :id)
                      :label (or (plist-get v :label) (plist-get v :id))
                      :value (health-chart-eas--null (plist-get v :value))
                      :unit (health-chart-eas--null (plist-get v :unit))
                      :date (health-chart-eas--null (plist-get v :date))
                      :as_of (health-chart-eas--null (plist-get v :as-of))
                      :marker (health-chart-eas--null (plist-get v :marker))
                      :person (health-chart-eas--null (plist-get v :person))
                      :cohort (health-chart-eas--null (plist-get v :cohort))))
              data)))))

(eas-register-adapter
 "indicator-values"
 :doc "health-chart indicator values as rows {id, label, value, unit, date, as_of, marker, person, cohort}; plists, alists or JSON objects."
 :example (health-chart--example-indicator-values)
 :convert #'health-chart-eas--convert-indicators)

;;; status transform

(defun health-chart-eas--status (rows _params)
  "Add status, glyph, status_label, value_label and out to ROWS."
  (seq-map
   (lambda (row)
     (let* ((m (health-chart-eas--row-measurement row))
            (status (health-chart-status m)))
       (health-chart-eas--put row
                              :status (symbol-name status)
                              :glyph (health-chart-status-glyph status)
                              :status_label (health-chart-status-label status)
                              :value_label (health-chart-fmt-value m)
                              :value_text (health-chart-fmt (plist-get m :value))
                              :out (if (memq status '(low high)) 1 0))))
   rows))

(eas-register-transform
 "status"
 :doc "Judge each biomarker row's value against its ranges: adds status (optimal, normal, suboptimal, low, high, unknown), glyph, status_label (glyph and word, so color is never the only channel), value_label (value and unit), value_text (the number alone) and out (1 when below or above the reference range)."
 :schema '()
 :fn #'health-chart-eas--status)

;;; reference-band transform

(defun health-chart-eas--group-ranges (rows)
  "The ranges of ROWS (a list of one marker's rows): the latest draw's."
  (health-chart-ranges (mapcar #'health-chart-eas--row-measurement rows)))

(defun health-chart-eas--bands (ranges params)
  "The (:ref BAND :opt BAND) RANGES yields under PARAMS' ref and optimal."
  (health-chart-model--bands
   ranges
   (append (when (plist-member params :ref) (list :ref (eas-true-p (plist-get params :ref))))
           (when (plist-member params :optimal)
             (list :optimal (eas-true-p (plist-get params :optimal)))))))

(defun health-chart-eas--band-labels (bands)
  "(:ref_label S :opt_label S) naming BANDS' ranges."
  (let ((ref (plist-get bands :ref)) (opt (plist-get bands :opt)))
    (list :ref_label (if ref (format "reference %s" (health-chart-fmt-range (car ref) (cdr ref))) "")
          :opt_label (if opt (format "optimal %s" (health-chart-fmt-range (car opt) (cdr opt))) ""))))

(defun health-chart-eas--lollipop-base (bands values)
  "(BASE WORD LIMIT) of the stems of VALUES under BANDS, as the lollipop kind."
  (let* ((target (or (plist-get bands :opt) (plist-get bands :ref)))
         (edge (or (cdr target) (car target))))
    (list (or edge (min 0 (apply #'min values)))
          (cond ((null edge) "baseline") ((plist-get bands :opt) "optimal") (t "reference"))
          (if (cdr target) "limit" "minimum"))))

(defun health-chart-eas--value-columns (rows params)
  "ROWS (one marker's) with band extents in value units under PARAMS."
  (let* ((ranges (health-chart-eas--group-ranges rows))
         (bands (health-chart-eas--bands ranges params))
         (values (delq nil (mapcar (lambda (r) (health-chart-eas--num (plist-get r :value))) rows)))
         (domain (plist-get params :domain))
         (base (when (eas-true-p (plist-get params :base))
                 (health-chart-eas--lollipop-base bands values)))
         (range (cond
                 ((and (vectorp domain) (= (length domain) 2))
                  (cons (aref domain 0) (aref domain 1)))
                 (values
                  (let ((rng (health-chart-model--y-range values bands)))
                    (when base
                      ;; headroom above the tallest stem for its label
                      (let ((pad (* 0.05 (- (cdr rng) (car rng)))))
                        (setq rng (cons (min (car rng) (- (car base) pad))
                                        (+ (max (cdr rng) (+ (car base) pad)) (* 2 pad))))))
                    (health-chart-spec--floor-zero rng values)))))
         (ref (and range (health-chart-spec--band-extent (plist-get bands :ref) range)))
         (opt (and range (health-chart-spec--band-extent (plist-get bands :opt) range)))
         (labels (health-chart-eas--band-labels bands))
         (unit (let ((u (plist-get (car (last rows)) :unit))) (if (stringp u) u "")))
         (limit (when (eas-true-p (plist-get params :limit))
                  ;; the reference limit, else the optimal one, as a threshold line
                  (let* ((target (or (plist-get bands :ref) (plist-get bands :opt)))
                         (edge (or (cdr target) (car target))))
                    (when edge
                      (list edge (format "%s %s%s" (plist-get (car rows) :label)
                                         (if (cdr target) "≤" "≥") (health-chart-fmt edge))))))))
    (mapcar
     (lambda (row)
       (apply #'health-chart-eas--put row
              :y_lo (and range (health-chart-spec--round (car range)))
              :y_hi (and range (health-chart-spec--round (cdr range)))
              :ref_y (car ref) :ref_y2 (cdr ref) :opt_y (car opt) :opt_y2 (cdr opt)
              :ref_label (plist-get labels :ref_label) :opt_label (plist-get labels :opt_label)
              :band_note (string-join (seq-remove #'string-empty-p
                                                  (list (plist-get labels :ref_label)
                                                        (plist-get labels :opt_label)))
                                      " · ")
              (append
               (when limit (list :limit (car limit) :limit_label (cadr limit)))
               (when base
                (let* ((b (car base))
                       (gap (- (or (health-chart-eas--num (plist-get row :value)) b) b)))
                  (list :base (health-chart-spec--round b)
                        :gap (health-chart-spec--round gap 4)
                        :gap_label (format "%s%s" (if (>= gap 0) "+" "−") (health-chart-fmt (abs gap)))
                        :base_label (format "%s %s %s%s" (nth 1 base) (nth 2 base)
                                            (health-chart-fmt b)
                                            (if (string-empty-p unit) "" (concat " " unit)))))))))
     rows)))

(defun health-chart-eas--bullet-columns (rows params)
  "ROWS (one per marker, the latest draw) with 0..1 positions in a padded domain.
PARAMS' ref and optimal say which bands to place."
  (mapcar
   (lambda (row)
     (let* ((bands (health-chart-eas--bands (health-chart-eas--row-measurement row) params))
            (ref (plist-get bands :ref)) (opt (plist-get bands :opt))
            (v (health-chart-eas--num (plist-get row :value)))
            (finite (delq nil (list v (car ref) (cdr ref) (car opt) (cdr opt))))
            (lo (apply #'min finite)) (hi (apply #'max finite))
            (pad (* 0.12 (max (- hi lo) (* 0.2 (abs (or v 0))) 1e-6)))
            (dom (cons (if (and (>= lo 0) (< (- lo pad) 0)) 0 (- lo pad)) (+ hi pad)))
            (pos (lambda (x) (health-chart-spec--position x dom))))
       (health-chart-eas--put
        row
        :domain_lo (health-chart-spec--round (car dom))
        :domain_hi (health-chart-spec--round (cdr dom))
        :pos (funcall pos v)
        :ref_x (and ref (or (funcall pos (car ref)) 0))
        :ref_x2 (and ref (or (funcall pos (cdr ref)) 1))
        :opt_x (and opt (or (funcall pos (car opt)) 0))
        :opt_x2 (and opt (or (funcall pos (cdr opt)) 1))
        :ref_range (if ref (health-chart-fmt-range (car ref) (cdr ref)) "")
        :opt_range (if opt (health-chart-fmt-range (car opt) (cdr opt)) ""))))
   rows))

(defun health-chart-eas--column-names (column)
  "(NORM X CLIPPED) column keys for value COLUMN (a string): norm, x for value."
  (if (equal column "value")
      (list :norm :x :clipped)
    (list (eas-key (concat "norm_" column)) (eas-key (concat "x_" column))
          (eas-key (concat "clipped_" column)))))

(defun health-chart-eas--range-columns (rows params)
  "ROWS with positions on each marker's reference range (0 at low, 1 at high).
Markers with no scale (no ranges at all) are dropped.  PARAMS' of lists
the value columns to place (default value)."
  (let* ((columns (append (or (plist-get params :of) ["value"]) nil))
         (groups (health-chart-eas--group-rows rows :marker))
         (scaled (seq-filter
                  (lambda (g) (health-chart-spec-gallery--scale
                               (health-chart-eas--group-ranges (cdr g))))
                  groups))
         (norms (cl-loop for g in scaled
                         for sc = (health-chart-spec-gallery--scale
                                   (health-chart-eas--group-ranges (cdr g)))
                         append (cl-loop for row in (cdr g)
                                         append (cl-loop for c in columns
                                                         for v = (health-chart-eas--num
                                                                  (plist-get row (eas-key c)))
                                                         when v collect (health-chart-spec-gallery--norm v sc)))))
         (dom (and norms (health-chart-spec-gallery--norm-domain norms))))
    (cl-loop
     for g in scaled
     for ranges = (health-chart-eas--group-ranges (cdr g))
     for sc = (health-chart-spec-gallery--scale ranges)
     for bands = (health-chart-eas--bands ranges params)
     for opt = (health-chart-spec-gallery--band-x (plist-get bands :opt) sc dom)
     append
     (mapcar
      (lambda (row)
        (apply
         #'health-chart-eas--put row
         :x_lo (car dom) :x_hi (cdr dom)
         :ref_x (and (plist-get bands :ref) 0) :ref_x2 (and (plist-get bands :ref) 1)
         :opt_x (car opt) :opt_x2 (cdr opt)
         :ref_range (health-chart-fmt-range (plist-get ranges :ref-low) (plist-get ranges :ref-high))
         :opt_range (health-chart-fmt-range (plist-get ranges :opt-low) (plist-get ranges :opt-high))
         (cl-loop for c in columns
                  for v = (health-chart-eas--num (plist-get row (eas-key c)))
                  for (norm-key x-key clipped-key) = (health-chart-eas--column-names c)
                  when v
                  append (let* ((norm (health-chart-spec-gallery--norm v sc))
                                (x (health-chart-spec--clamp norm (car dom) (cdr dom))))
                           (list norm-key (health-chart-spec--round norm 4)
                                 x-key (health-chart-spec--round x 4)
                                 clipped-key (if (= x norm) 0 1))))))
      (cdr g)))))

(defun health-chart-eas--x-domain (rows)
  "The (LO . HI) dates of the time axis over ROWS.
Their extent padded by 4%, 20 days at least."
  (let ((days (delq nil (mapcar (lambda (r) (and (stringp (plist-get r :date))
                                                 (health-chart-date-days (plist-get r :date))))
                                (append rows nil)))))
    (when days
      (let* ((d0 (apply #'min days)) (d1 (apply #'max days))
             (pad (max 20 (round (* 0.04 (- d1 d0))))))
        (cons (health-chart-days-date (- d0 pad)) (health-chart-days-date (+ d1 pad)))))))

(defun health-chart-eas--reference-band (rows params)
  "Add range-band columns to ROWS for PARAMS' scale (value, domain or range)."
  (pcase (or (plist-get params :scale) "value")
    ("value" (let ((x (health-chart-eas--x-domain rows)))
               (mapcar (lambda (r) (health-chart-eas--put r :x_lo (car x) :x_hi (cdr x)))
                       (cl-loop for g in (health-chart-eas--group-rows rows :marker)
                                append (health-chart-eas--value-columns (cdr g) params)))))
    ("domain" (health-chart-eas--bullet-columns (append rows nil) params))
    ("range" (health-chart-eas--range-columns rows params))
    (other (eas-signal "INVALID_INPUT"
                       (format "reference-band scale must be value, domain or range, got %S" other)
                       :transform "reference-band" :field "scale"))))

(eas-register-transform
 "reference-band"
 :doc "Reference and optimal bands for biomarker rows, from each marker's latest ranges. scale value: band extents ref_y, ref_y2, opt_y, opt_y2 clamped to the marker's padded value range y_lo..y_hi (labels ref_label, opt_label, band_note), and the padded date range x_lo..x_hi of all the rows. scale domain: each row's value and bands as 0..1 positions (pos, ref_x, ref_x2, opt_x, opt_x2) in its own padded domain, for one row per marker. scale range: positions on the reference range (0 = low, 1 = high; norm, x clamped to a shared display domain x_lo..x_hi, clipped), markers with no ranges dropped."
 :schema '(:scale (:type "string" :default "value" :doc "value, domain or range")
           :domain (:type "array" :doc "scale value: [lo, hi] of the value axis, else computed")
           :ref (:type "boolean" :doc "show the reference band (default `health-chart-show-ref-range')")
           :optimal (:type "boolean" :doc "show the optimal band (default `health-chart-show-optimal-range')")
           :base (:type "boolean" :doc "scale value: add the lollipop's base, gap and labels and widen the range for stems")
           :limit (:type "boolean" :doc "scale value: add limit and limit_label, the target's upper (else lower) edge, as a threshold")
           :of (:type "array" :doc "scale range: the value columns to place, default [\"value\"]"))
 :fn #'health-chart-eas--reference-band)

;;; change transform

(defun health-chart-eas--with-lim (rows)
  "ROWS with lim, a symmetric axis bound with room for the end labels."
  (let ((lim (ceiling (* 2.2 (apply #'max 1 (mapcar (lambda (r) (abs (plist-get r :pct))) rows))))))
    (mapcar (lambda (r) (health-chart-eas--put r :lim lim)) rows)))

(defun health-chart-eas--change (rows _params)
  "One row per marker of ROWS with two or more draws: the last draw and its change.
The row is the last draw's, plus before and after (values), date_before,
date_after, change, pct, pct_label, verdict, verdict_glyph,
verdict_label, change_label and span_label."
  (health-chart-eas--with-lim
   (cl-loop
   for g in (health-chart-eas--group-rows rows :marker)
   for draws = (health-chart-eas--sorted-by-date (cdr g))
   when (cdr draws)
   collect
   (let* ((b (car draws)) (a (car (last draws)))
          (bm (health-chart-eas--row-measurement b)) (am (health-chart-eas--row-measurement a))
          (bv (plist-get bm :value)) (av (plist-get am :value))
          (pct (unless (zerop bv) (* 100.0 (/ (- av bv) (float (abs bv))))))
          (verdict (health-chart-model--verdict bm am))
          (unit (or (plist-get am :unit) "")))
     (health-chart-eas--put
      a
      :before bv :after av :date_before (plist-get b :date) :date_after (plist-get a :date)
      :change (health-chart-spec--round (- av bv))
      :pct (health-chart-spec--round (or pct 0) 1)
      :pct_label (if pct (format "%+.1f%%" pct) "n/a")
      :side (if (< (or pct 0) 0) "neg" "pos")
      :verdict (if verdict (symbol-name verdict) "unknown")
      :verdict_glyph (if verdict (alist-get verdict health-chart-verdict-glyphs "?") "?")
      :verdict_label (health-chart-spec--verdict-label verdict)
      :change_label (string-trim-right
                     (format "%s → %s %s" (health-chart-fmt bv) (health-chart-fmt av) unit))
      :span_label (format "%s → %s"
                          (health-chart-format-date (plist-get b :date) "%b %Y")
                          (health-chart-format-date (plist-get a :date) "%b %Y")))))))

(eas-register-transform
 "change"
 :doc "Per marker, the change between its first and last draw in the rows: before, after, change, pct, pct_label, verdict (improved, worsened, on-target, steady or unknown, judged toward the optimal range else the reference), verdict_glyph, verdict_label, change_label, span_label, and lim (a symmetric axis bound with room for labels). Markers with one draw are dropped; the row is the last draw's."
 :schema '()
 :fn #'health-chart-eas--change)

;;; staleness transform

(defun health-chart-eas--staleness (rows params)
  "Days from each indicator row's date to the as-of date, with freshness state.
ROWS are indicator rows; PARAMS give as_of, due_days and stale_days."
  (let* ((rows (append rows nil))
         (given (lambda (key) (let ((v (plist-get params key)))
                                (and v (not (member v '("" 0 :null :false))) v))))
         (as-of (or (funcall given :as_of)
                    (car (last (sort (seq-filter #'stringp (mapcar (lambda (r) (plist-get r :as_of)) rows))
                                     #'string<)))
                    (format-time-string "%Y-%m-%d")))
         (due (or (funcall given :due_days) health-chart-indicator-due-days))
         (stale (or (funcall given :stale_days) health-chart-indicator-stale-days))
         (now (health-chart-date-days as-of))
         (out (mapcar
               (lambda (row)
                 (let* ((date (plist-get row :date))
                        (days (and (stringp date) (- now (health-chart-date-days date))))
                        (state (health-chart-model-staleness-state days due stale)))
                   (health-chart-eas--put
                    row :days days :bar (or days 0)
                    :days_label (if days (format "%d d" days) "no draw")
                    :state (symbol-name state)
                    :glyph (alist-get state health-chart-staleness-glyphs "?")
                    :state_label (health-chart-staleness-label state)
                    :due due :stale stale :as_of_date as-of)))
               rows))
         (scale (max 1 (round (* 1.25 stale))
                     (apply #'max 0 (delq nil (mapcar (lambda (r) (health-chart-eas--num (plist-get r :days)))
                                                      out))))))
    (mapcar (lambda (row) (health-chart-eas--put row :scale scale))
            (seq-sort-by (lambda (r) (or (health-chart-eas--num (plist-get r :days)) most-negative-fixnum))
                         #'> out))))

(eas-register-transform
 "staleness"
 :doc "Days since each indicator row's draw, against due and stale thresholds: days, bar, days_label, state (fresh, due, stale, undated), glyph, state_label, due, stale, as_of_date, scale (days a full bar spans). Stalest first, undated last."
 :schema '(:as_of (:type "string" :doc "date the draws are judged at (default the rows' latest as_of, else today)")
           :due_days (:type "integer" :doc "default `health-chart-indicator-due-days'")
           :stale_days (:type "integer" :doc "default `health-chart-indicator-stale-days'"))
 :fn #'health-chart-eas--staleness)

;;; trend transform

(defun health-chart-eas--trend (rows _params)
  "Add roll, fit and trend_label to ROWS, one marker's draws."
  (let* ((rows (health-chart-eas--sorted-by-date (append rows nil)))
         (vals (mapcar (lambda (r) (plist-get r :value)) rows))
         (days (mapcar (lambda (r) (health-chart-date-days (plist-get r :date))) rows))
         (fit (health-chart-spec-gallery--fit days vals))
         (n (length rows))
         (unit (let ((u (plist-get (car (last rows)) :unit))) (if (stringp u) u "")))
         (per-year (and fit (* 365.25 (car fit))))
         (span (- (car (last days)) (car days)))
         (level (/ (apply #'+ (mapcar #'abs vals)) (max 1 n)))
         (words (and fit (health-chart-spec-gallery--direction
                          (car fit) (/ (* (car fit) span) (max 1e-9 level)))))
         (label (if fit
                    (format "%s %s%s per year" words (health-chart-fmt (abs per-year))
                            (if (string-empty-p unit) "" (concat " " unit)))
                  "trend needs three draws")))
    (cl-loop for r in rows for i from 0
             collect (health-chart-eas--put
                      r
                      :roll (health-chart-spec--round
                             (let ((w (seq-subseq vals (max 0 (1- i)) (min n (+ i 2)))))
                               (/ (apply #'+ w) (float (length w))))
                             4)
                      :fit (and fit (health-chart-spec--round
                                     (+ (nth 2 fit) (* (car fit) (- (nth i days) (nth 1 fit)))) 4))
                      :slope_per_year (and per-year (health-chart-spec--round per-year 4))
                      :trend_label label))))

(eas-register-transform
 "trend"
 :doc "One marker's draws with roll (centred mean of up to three draws), fit (least-squares line at the draw's date), slope_per_year and trend_label (the slope in words; \"trend needs three draws\" below three)."
 :schema '()
 :fn #'health-chart-eas--trend)

;;; templates

(defconst health-chart-eas-template-directory
  (expand-file-name "templates/eas"
                    (file-name-directory (or load-file-name buffer-file-name default-directory)))
  "Health-chart's eas templates (health-timeseries, health-bullet, ...).")

(add-to-list 'eas-template-directories health-chart-eas-template-directory t)
(eas-template-reload)

(provide 'health-chart-eas)
;;; health-chart-eas.el ends here
