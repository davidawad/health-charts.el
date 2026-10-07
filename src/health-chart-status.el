;;; health-chart-status.el --- The one color rule: red, yellow, green, grey -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Every template that judges a value against a range uses this rule:
;;
;;   low / high   the value is outside [LOW, HIGH]            red
;;   near         inside the range but within the margin
;;                of a limit (the limit itself included)      yellow
;;   ok           inside the range, clear of both margins     green
;;   unknown      no usable range, or the value is no number  grey
;;
;; The margin is a fraction of the range width (default 0.2, see
;; `health-chart-theme'), measured inward from each bound.  A one-sided
;; range (only LOW or only HIGH) uses the fraction of that bound's
;; magnitude instead, since it has no width.  A value exactly at a limit
;; is in range (near, not low or high); one exactly at the inner edge
;; of the margin is ok.  Per row (or per call) WARN-LOW and WARN-HIGH
;; replace the computed inner edges, and a margin replaces the default.
;;
;; The rule needs no clinical knowledge: the limits come from the data.
;; It is registered with eas as the transform "health-status", which
;; adds `status', `status_label', `status_glyph', `status_flag' and
;; `range_text' to every row; for a constant range also the fields that
;; draw its band, and for range-bar charts `pos' and the warning edges.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'eas)
(require 'health-chart-theme)

(defconst health-chart-status-labels
  '((low . "low") (near . "near limit") (ok . "in range")
    (high . "high") (unknown . "no range"))
  "The legend words of each status, in legend order.
Templates list the same words in their color scale's domain.")

(defconst health-chart-status-glyphs
  '((low . "\u25bc") (near . "\u25c6") (ok . "\u25cf") (high . "\u25b2") (unknown . "?"))
  "One character per status, for cells too small for a legend.")

(defconst health-chart-status-shapes
  '("triangle-down" "diamond" "circle" "triangle-up" "square")
  "The mark shapes of the statuses in `health-chart-status-labels' order.")

(defun health-chart-status--num (x)
  "X when it is a finite number, else nil."
  (and (numberp x) (or (integerp x) (and (not (isnan x)) (< (abs x) 1.0e+INF))) x))

(defun health-chart-status-limits (low high &optional margin warn-low warn-high)
  "The warning zone edges of the range LOW..HIGH, as (WARN-LOW . WARN-HIGH).
Either limit may be nil (a one-sided range).  MARGIN is a fraction,
default `health-chart-theme' :warn-margin.  An explicit WARN-LOW or
WARN-HIGH is taken as is.  An edge is nil where its limit is."
  (let* ((m (or (health-chart-status--num margin) (health-chart-theme-get :warn-margin)))
         (low (health-chart-status--num low))
         (high (health-chart-status--num high))
         (width (and low high (- high low))))
    (cons (and low (or (health-chart-status--num warn-low)
                       (+ low (* m (or width (abs low))))))
          (and high (or (health-chart-status--num warn-high)
                        (- high (* m (or width (abs high)))))))))

(defun health-chart-status (value low high &optional margin warn-low warn-high)
  "The status of VALUE against the range LOW..HIGH.
One of `low', `high' (out of range), `near' (inside, within the margin
of a limit), `ok', or `unknown' (no limit given, or VALUE no number).
MARGIN, WARN-LOW and WARN-HIGH are as in `health-chart-status-limits'."
  (let ((v (health-chart-status--num value))
        (low (health-chart-status--num low))
        (high (health-chart-status--num high)))
    (if (or (null v) (and (null low) (null high)))
        'unknown
      (pcase-let ((`(,wl . ,wh) (health-chart-status-limits low high margin warn-low warn-high)))
        (cond ((and low (< v low)) 'low)
              ((and high (> v high)) 'high)
              ((and wl (< v wl)) 'near)
              ((and wh (> v wh)) 'near)
              (t 'ok))))))

(defun health-chart-status-label (status &optional labels)
  "The legend word of STATUS, from LABELS (an alist) or the default words."
  (cdr (assq status (or labels health-chart-status-labels))))

;;; The eas transform

(defun health-chart-status--field (row name)
  "ROW's numeric value of the field NAME (a string or nil), else nil."
  (and name (health-chart-status--num (plist-get row (eas-key name)))))

(defun health-chart-status--labels (params)
  "The status labels, `health-chart-status-labels' with PARAMS' :labels laid over."
  (let ((over (plist-get params :labels)))
    (mapcar (lambda (entry)
              (let ((word (and (eas-object-p over) (plist-get over (eas-key (symbol-name (car entry)))))))
                (cons (car entry) (if (stringp word) word (cdr entry)))))
            health-chart-status-labels)))

(defun health-chart-status--number-text (n)
  "N as short text: whole numbers without a decimal point."
  (if (and (floatp n) (= n (ftruncate n)) (< (abs n) 1.0e15))
      (format "%d" n)
    (format "%s" n)))

(defun health-chart-status-range-text (low high)
  "LOW and HIGH as text: \"3.9 to 5.6\", a one-sided limit, or \"no range\"."
  (let ((low (health-chart-status--num low)) (high (health-chart-status--num high)))
    (cond ((and low high) (format "%s to %s" (health-chart-status--number-text low)
                                  (health-chart-status--number-text high)))
          (low (format "\u2265 %s" (health-chart-status--number-text low)))
          (high (format "\u2264 %s" (health-chart-status--number-text high)))
          (t "no range"))))

(defun health-chart-status-span (low high)
  "The span (LO . HI) a range is drawn over, or nil when it has no limit.
LOW..HIGH as given when both exist.  A range with one limit has no width:
an upper limit alone is drawn from one magnitude below it, a lower limit
alone up to one magnitude above it (so the bar starts at 0 for a positive
upper limit)."
  (let ((low (health-chart-status--num low)) (high (health-chart-status--num high)))
    (cond ((and low high) (cons low (if (= low high) (1+ low) high)))
          (high (cons (- high (if (zerop high) 1 (abs high))) high))
          (low (cons low (+ low (if (zerop low) 1 (abs low))))))))

(defun health-chart-status--position (value low high margin warn-low warn-high)
  "Layout fields for VALUE against LOW..HIGH as a plist.
:pos is VALUE with the span (`health-chart-status-span') mapped to 0..1
and clamped to -0.5..1.5; :warn_lo_pos and :warn_hi_pos are the inner
edges of the warning zones on the same scale; :ok_from and :ok_to bound
the green part of the bar.  Empty without a limit.
MARGIN, WARN-LOW and WARN-HIGH are as in `health-chart-status-limits'."
  (when-let* ((span (health-chart-status-span low high))
              (lo (car span))
              (w (- (cdr span) lo)))
    (pcase-let ((`(,wl . ,wh) (health-chart-status-limits low high margin warn-low warn-high)))
      (let ((from (if wl (/ (- wl lo) (float w)) 0.0))
            (to (if wh (/ (- wh lo) (float w)) 1.0)))
        (append (and (health-chart-status--num value)
                     (list :pos (max -0.5 (min 1.5 (/ (- value lo) (float w))))))
                (and wl (list :warn_lo_pos from))
                (and wh (list :warn_hi_pos to))
                (list :ok_from from :ok_to (max from to)))))))

(defun health-chart-status--band (rows value-field low high margin wlow whigh)
  "Fields that draw the range LOW..HIGH as a band behind ROWS' VALUE-FIELD.
:band_lo and :band_hi are the band's ends; a missing limit is replaced
by the extent of the values and the other limit, plus a tenth.
:zone_low and :zone_high are the inner edges of the warning zones."
  (when (or low high)
    (let* ((values (delq nil (mapcar (lambda (row) (health-chart-status--field row value-field))
                                     (append rows nil))))
           (lo (apply #'min (delq nil (append (list low high) values))))
           (hi (apply #'max (delq nil (append (list low high) values))))
           (pad (* 0.1 (max (- hi lo) (abs hi) 1)))
           (edges (health-chart-status-limits low high margin wlow whigh)))
      (append (list :band_lo (or low (- lo pad)) :band_hi (or high (+ hi pad)))
              (and (car edges) (list :zone_low (car edges)))
              (and (cdr edges) (list :zone_high (cdr edges)))))))

(defun health-chart-status--out-key (key prefix)
  "The output field KEY is written to when PREFIX (a string or nil) is set."
  (car (health-chart-status--rename (list key nil) prefix)))

(defun health-chart-status--rename (plist prefix)
  "PLIST with every key renamed for PREFIX (a string), or PLIST when PREFIX is nil.
`status' becomes PREFIX, `status_label' PREFIX_label, `range_text'
PREFIX_range_text, and so on."
  (if (not (stringp prefix))
      plist
    (cl-loop for (k v) on plist by #'cddr
             for name = (substring (symbol-name k) 1)
             append (list (eas-key (cond ((equal name "status") prefix)
                                         ((string-prefix-p "status_" name)
                                          (concat prefix (substring name 6)))
                                         (t (concat prefix "_" name))))
                          v))))

(defun health-chart-status--transform (rows params)
  "Add the status fields to ROWS; PARAMS are those of the registered transform."
  (let* ((value-field (or (plist-get params :value) "value"))
         (low-field (plist-get params :low_field))
         (high-field (plist-get params :high_field))
         (labels (health-chart-status--labels params))
         (margin (plist-get params :margin))
         (normalize (eas-true-p (plist-get params :normalize)))
         (added (mapcar (lambda (k) (list (health-chart-status--out-key k (plist-get params :prefix))))
                        '(:status :status_label :status_glyph :status_flag :range_text :pos
                          :warn_lo_pos :warn_hi_pos :ok_from :ok_to :band_lo :band_hi
                          :zone_low :zone_high)))
         (band (and (not low-field) (not high-field)
                    (health-chart-status--band
                     rows value-field (health-chart-status--num (plist-get params :low))
                     (health-chart-status--num (plist-get params :high)) margin
                     (plist-get params :warn_low) (plist-get params :warn_high)))))
    (seq-into
     (seq-map
      (lambda (row)
        (let* ((value (plist-get row (eas-key value-field)))
               (low (if low-field (health-chart-status--field row low-field) (plist-get params :low)))
               (high (if high-field (health-chart-status--field row high-field) (plist-get params :high)))
               (m (or (health-chart-status--field row "warn_margin") margin))
               (wlow (or (health-chart-status--field row "warn_low") (plist-get params :warn_low)))
               (whigh (or (health-chart-status--field row "warn_high") (plist-get params :warn_high)))
               (status (health-chart-status value low high m wlow whigh)))
          (append (cl-loop for (k v) on row by #'cddr
                           unless (assq k added) append (list k v))
                  (health-chart-status--rename
                   (append band
                           (list :status (symbol-name status)
                                 :status_label (health-chart-status-label status labels)
                                 :status_glyph (cdr (assq status health-chart-status-glyphs))
                                 :status_flag (pcase status ('low "L") ('high "H") (_ ""))
                                 :range_text (health-chart-status-range-text low high))
                           (and normalize
                                (health-chart-status--position value low high m wlow whigh)))
                   (plist-get params :prefix)))))
      rows)
     'vector)))

(eas-register-transform
 "health-status"
 :doc "Judge each row's VALUE against a range and add status (low, near, ok, high, unknown), status_label (the legend word), status_glyph and status_flag (L, H or empty).  The range is the constants LOW and HIGH, or per row the fields LOW_FIELD and HIGH_FIELD; either may be missing (one-sided), both missing is unknown.  Rows may carry warn_low, warn_high and warn_margin to override the warning zone."
 :schema '(:value (:type "string" :default "value" :doc "the numeric field to judge")
           :low (:type "number" :doc "lower limit of the range")
           :high (:type "number" :doc "upper limit of the range")
           :low_field (:type "string" :doc "row field holding the lower limit")
           :high_field (:type "string" :doc "row field holding the upper limit")
           :warn_low (:type "number" :doc "inner edge of the warning zone at the low limit")
           :warn_high (:type "number" :doc "inner edge of the warning zone at the high limit")
           :margin (:type "number" :doc "warning margin as a fraction of the range width")
           :prefix (:type "string" :doc "name the added fields PREFIX, PREFIX_label, PREFIX_glyph, PREFIX_flag, PREFIX_range_text ... instead of status, status_label ... (judge two fields in one pass)")
           :labels (:type "object" :doc "legend words by status: low, near, ok, high, unknown")
           :normalize (:type "boolean" :doc "also add pos, warn_lo_pos, warn_hi_pos, ok_from and ok_to: the value, the warning edges and the green part with the range drawn over 0..1"))
 :fn #'health-chart-status--transform)

;;; Category bands

(defconst health-chart-status-band-statuses '("low" "near" "ok" "high")
  "The status a category band may carry; the same words as the range rule.")

(defun health-chart-status-band-of (value bands)
  "The band of BANDS (a list or vector of plists) holding VALUE, or nil.
A band holds LOW <= VALUE < HIGH; the topmost band also holds its HIGH."
  (let* ((bands (append bands nil))
         (top (and bands (apply #'max (mapcar (lambda (b) (or (plist-get b :high) 0)) bands)))))
    (and (health-chart-status--num value)
         (seq-find (lambda (b)
                     (let ((lo (health-chart-status--num (plist-get b :low)))
                           (hi (health-chart-status--num (plist-get b :high))))
                       (and lo hi (<= lo value)
                            (or (< value hi) (and (= value hi) (= hi top))))))
                   bands))))

(defun health-chart-status-band (value bands)
  "The status of VALUE from the category BANDS, as `health-chart-status'.
Each band is a plist {:label :low :high :status}, :status being low,
near, ok or high.  `unknown' when no band holds VALUE or the band
names no status."
  (let ((status (plist-get (health-chart-status-band-of value bands) :status)))
    (if (and (stringp status) (member status health-chart-status-band-statuses))
        (intern status)
      'unknown)))

(defun health-chart-status-bands (low high &optional margin lowest highest)
  "Category bands for the range LOW..HIGH, as a vector of plists.
MARGIN is as in `health-chart-status-limits'.  The bands are
{:label :low :high :status}: low (below LOW), near, ok, near, then
high (above HIGH), cut where `health-chart-status-limits' puts the
warning zones.  LOWEST and HIGHEST close the outer bands (default: one
range width, or one bound's magnitude, beyond the limit).  A missing
limit leaves out its side."
  (let* ((low (health-chart-status--num low)) (high (health-chart-status--num high))
         (span (health-chart-status-span low high))
         (edges (health-chart-status-limits low high margin))
         (width (and span (- (cdr span) (car span))))
         (lowest (or lowest (and low (if (>= low 0) (max 0 (- low width)) (- low width)))))
         (highest (or highest (and high (+ high width)))))
    (vconcat
     (and low (< lowest low) (list (list :label "low" :low lowest :high low :status "low")))
     (and low (list (list :label "near limit" :low low :high (car edges) :status "near")))
     (list (list :label "in range" :low (or (car edges) (and span (car span)))
                 :high (or (cdr edges) (and span (cdr span))) :status "ok"))
     (and high (list (list :label "near limit" :low (cdr edges) :high high :status "near")))
     (and high (list (list :label "high" :low high :high highest :status "high"))))))

(defun health-chart-status--band-transform (rows params)
  "Add the status fields to ROWS from the category bands in PARAMS."
  (let* ((value-field (or (plist-get params :value) "value"))
         (bands (append (plist-get params :bands) nil))
         (labels (health-chart-status--labels params)))
    (seq-into
     (seq-map
      (lambda (row)
        (let* ((value (plist-get row (eas-key value-field)))
               (band (health-chart-status-band-of value bands))
               (status (health-chart-status-band value bands)))
          (append (cl-loop for (k v) on row by #'cddr
                           unless (memq k '(:status :status_label :status_glyph :status_flag
                                            :band_label))
                           append (list k v))
                  (list :status (symbol-name status)
                        :status_label (health-chart-status-label status labels)
                        :status_glyph (cdr (assq status health-chart-status-glyphs))
                        :status_flag (pcase status ('low "L") ('high "H") (_ ""))
                        :band_label (or (plist-get band :label) "no band")))))
      rows)
     'vector)))

(eas-register-transform
 "health-band-status"
 :doc "Judge each row's VALUE by the category band that holds it (bands {label, low, high, status} from the data source, status low, near, ok or high) and add status, status_label, status_glyph, status_flag and band_label."
 :schema '(:value (:type "string" :default "value" :doc "the numeric field to judge")
           :bands (:type "array" :required t :doc "category bands {label, low, high, status}")
           :labels (:type "object" :doc "legend words by status: low, near, ok, high, unknown"))
 :fn #'health-chart-status--band-transform)

(provide 'health-chart-status)
;;; health-chart-status.el ends here
