;;; health-chart-core.el --- Shared configuration, faces and helpers for health-chart -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; The backend-neutral base every health-chart module builds on: the
;; `health-charts' customization group, the error hierarchy, faces,
;; glyphs, and the pure helpers both renderers share -- date arithmetic,
;; number formatting, marker labels and categories, and the status of a
;; measurement against its reference and optimal ranges.
;;
;; A MEASUREMENT here is always the canonical plist
;;
;;   (:person "alex" :marker "ldl_c" :value 112.0 :unit "mg/dL"
;;    :date "2025-03-01" :ref-low 0 :ref-high 100 :opt-low nil
;;    :opt-high 70 :flag high)
;;
;; produced by `health-chart-source-normalize' from JSON, alists or
;; plists.  Nothing in this file knows the JSON field names.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(define-error 'health-chart-error "health-chart error")

(defgroup health-charts nil
  "Biomarker charts: time series, range bars, heatmaps, dashboards."
  :group 'tools
  :prefix "health-chart-")

;; -----------------------------------------------------------------------
;; Defaults
;; -----------------------------------------------------------------------

(defcustom health-chart-width 72
  "Default text chart width in columns, labels included."
  :type 'natnum
  :group 'health-charts)

(defcustom health-chart-height 10
  "Default text chart height in rows for time-series kinds."
  :type 'natnum
  :group 'health-charts)

(defcustom health-chart-show-ref-range t
  "Whether charts shade the reference range by default.
Override per call with the :ref prop."
  :type 'boolean
  :group 'health-charts)

(defcustom health-chart-show-optimal-range t
  "Whether charts shade the optimal range by default.
Override per call with the :optimal prop."
  :type 'boolean
  :group 'health-charts)

(defcustom health-chart-sparkline-width 12
  "Columns a sparkline occupies in the sparkline table."
  :type 'natnum
  :group 'health-charts)

(defcustom health-chart-date-format "%Y-%m-%d"
  "Format for full dates in chart labels.
Only %Y, %m, %d, %y and %b are expanded (dates are calendar days, never
times, so no time zone is involved)."
  :type 'string
  :group 'health-charts)

;; -----------------------------------------------------------------------
;; Markers: labels and categories
;; -----------------------------------------------------------------------

(defcustom health-chart-marker-labels
  '(("ldl_c" . "LDL-C") ("hdl_c" . "HDL-C") ("total_cholesterol" . "Total chol")
    ("triglycerides" . "Triglycerides") ("apob" . "ApoB") ("lpa" . "Lp(a)")
    ("glucose" . "Glucose") ("hba1c" . "HbA1c") ("insulin" . "Insulin")
    ("crp" . "hs-CRP") ("hs_crp" . "hs-CRP") ("vitamin_d" . "Vitamin D")
    ("tsh" . "TSH") ("ferritin" . "Ferritin") ("alt" . "ALT") ("ast" . "AST")
    ("creatinine" . "Creatinine") ("egfr" . "eGFR") ("testosterone" . "Testosterone"))
  "Display label for each marker id.
A marker without an entry is shown as its id with underscores as spaces."
  :type '(alist :key-type string :value-type string)
  :group 'health-charts)

(defcustom health-chart-marker-categories
  '(("lipids" "ldl_c" "hdl_c" "total_cholesterol" "triglycerides" "apob" "lpa")
    ("metabolic" "glucose" "hba1c" "insulin")
    ("inflammation" "crp" "hs_crp")
    ("vitamins" "vitamin_d" "ferritin" "b12")
    ("thyroid" "tsh" "free_t4")
    ("liver" "alt" "ast")
    ("kidney" "creatinine" "egfr")
    ("hormones" "testosterone"))
  "Panel categories: (CATEGORY MARKER...).
A measurement's own :category wins; markers in no category fall into
\"other\".  The dashboard's category filter offers these names."
  :type '(alist :key-type string :value-type (repeat string))
  :group 'health-charts)

(defun health-chart-marker-label (marker)
  "Display label for MARKER id."
  (or (cdr (assoc marker health-chart-marker-labels))
      (cdr (seq-find (lambda (entry) (health-chart-marker-equal (car entry) marker))
                     health-chart-marker-labels))
      (replace-regexp-in-string "_" " " (format "%s" marker))))

(defun health-chart-marker-category (m)
  "Category name of measurement M (or of M itself when a marker string)."
  (if (and (listp m) (plist-get m :category))
      (plist-get m :category)
    (let ((marker (if (stringp m) m (plist-get m :marker))))
      (or (car (seq-find (lambda (entry)
                           (seq-some (lambda (c) (health-chart-marker-equal c marker))
                                     (cdr entry)))
                         health-chart-marker-categories))
          "other"))))

;; -----------------------------------------------------------------------
;; Faces and glyphs
;; -----------------------------------------------------------------------

(defface health-chart-optimal '((t :inherit success))
  "Face for values inside the optimal range."
  :group 'health-charts)

(defface health-chart-normal '((t :inherit default))
  "Face for values inside the reference range."
  :group 'health-charts)

(defface health-chart-suboptimal '((t :inherit warning))
  "Face for values inside the reference range but outside the optimal range."
  :group 'health-charts)

(defface health-chart-out-of-range '((t :inherit error))
  "Face for values outside the reference range."
  :group 'health-charts)

(defface health-chart-dim '((t :inherit shadow))
  "Face for axes, labels and secondary annotations."
  :group 'health-charts)

(defface health-chart-accent '((t :inherit font-lock-keyword-face))
  "Face for headline numbers and the plotted line."
  :group 'health-charts)

(defface health-chart-ref-band '((t :inherit shadow))
  "Face for the shaded reference-range band."
  :group 'health-charts)

(defface health-chart-optimal-band '((t :inherit success))
  "Face for the shaded optimal-range band."
  :group 'health-charts)

(defface health-chart-improved '((t :inherit success))
  "Face for a change toward the target range."
  :group 'health-charts)

(defface health-chart-worsened '((t :inherit error))
  "Face for a change away from the target range."
  :group 'health-charts)

(defface health-chart-header '((t :inherit bold))
  "Face for chart and section titles."
  :group 'health-charts)

(defcustom health-chart-series-faces
  '(font-lock-keyword-face font-lock-function-name-face
    font-lock-string-face font-lock-constant-face)
  "Faces for overlaid series (one per person), in fixed order."
  :type '(repeat face)
  :group 'health-charts)

(defcustom health-chart-series-glyphs '(?● ?■ ?◆ ?★ ?✚ ?◉)
  "Point glyphs for overlaid series in text charts, in fixed order.
The glyph is the identity channel, so overlays never rely on color alone."
  :type '(repeat character)
  :group 'health-charts)

(defcustom health-chart-glyph-ref-band ?░
  "Glyph shading the reference range in text charts."
  :type 'character
  :group 'health-charts)

(defcustom health-chart-glyph-optimal-band ?▒
  "Glyph shading the optimal range in text charts."
  :type 'character
  :group 'health-charts)

(defcustom health-chart-glyph-connector ?·
  "Glyph joining consecutive points in text charts."
  :type 'character
  :group 'health-charts)

(defcustom health-chart-glyph-marker ?┃
  "Glyph marking the latest value on a text range bar."
  :type 'character
  :group 'health-charts)

(defcustom health-chart-status-glyphs
  '((optimal . "●") (normal . "○") (suboptimal . "◐")
    (low . "▼") (high . "▲") (unknown . "?"))
  "Glyph for each measurement status, used beside every flag label."
  :type '(alist :key-type symbol :value-type string)
  :group 'health-charts)

(defconst health-chart-statuses '(optimal normal suboptimal low high unknown)
  "Every status `health-chart-status' returns, best first.")

(defconst health-chart-blocks " ▁▂▃▄▅▆▇█"
  "Eighth-height block glyphs, index = filled eighths (0..8).")

(defun health-chart-status-face (status)
  "Face for STATUS."
  (pcase status
    ('optimal 'health-chart-optimal)
    ('normal 'health-chart-normal)
    ('suboptimal 'health-chart-suboptimal)
    ((or 'low 'high) 'health-chart-out-of-range)
    (_ 'health-chart-dim)))

(defun health-chart-status-glyph (status)
  "Glyph string for STATUS."
  (or (alist-get status health-chart-status-glyphs) "?"))

(defun health-chart-status-label (status)
  "Glyph and name for STATUS, e.g. \"▲ high\"."
  (format "%s %s" (health-chart-status-glyph status)
          (if (eq status 'unknown) "n/a" status)))

;; -----------------------------------------------------------------------
;; Dates -- calendar days, never times, so no time zone is involved.
;; -----------------------------------------------------------------------

(defconst health-chart-date-regexp
  "\\`\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)"
  "An ISO calendar date, optionally followed by a time we ignore.")

(defun health-chart-date-p (date)
  "Return non-nil when DATE begins with a real YYYY-MM-DD calendar date."
  (when-let* ((ymd (health-chart--parse-date date)))
    ;; 2025-02-31 does not exist: it would come back as a March day
    (equal (health-chart-days-date (apply #'health-chart--days-from-civil ymd))
           (substring date 0 10))))

(defun health-chart--parse-date (date)
  "Return (YEAR MONTH DAY) of DATE when it begins with YYYY-MM-DD, else nil."
  (when (and (stringp date) (string-match health-chart-date-regexp date))
    (let ((ymd (mapcar (lambda (i) (string-to-number (match-string i date))) '(1 2 3))))
      (when (and (<= 1 (nth 1 ymd) 12) (<= 1 (nth 2 ymd) 31))
        ymd))))

(defun health-chart--days-from-civil (y m d)
  "Days since 1970-01-01 of the proleptic Gregorian date Y M D.
Y is the year, M the month and D the day of the month."
  (let* ((y (if (<= m 2) (1- y) y))
         (era (floor y 400))
         (yoe (- y (* era 400)))
         (doy (+ (/ (+ (* 153 (+ m (if (> m 2) -3 9))) 2) 5) (1- d)))
         (doe (+ (* yoe 365) (/ yoe 4) (- (/ yoe 100)) doy)))
    (+ (* era 146097) doe -719468)))

(defun health-chart-date-days (date)
  "DATE (\"YYYY-MM-DD\") as days since 1970-01-01."
  (unless (health-chart-date-p date)
    (signal 'health-chart-error (list (format "not a YYYY-MM-DD date: %S" date)
                                      :code "invalid_date")))
  (apply #'health-chart--days-from-civil (health-chart--parse-date date)))

(defun health-chart-days-date (days)
  "DAYS since 1970-01-01 as a \"YYYY-MM-DD\" string."
  (let* ((z (+ days 719468))
         (era (floor z 146097))
         (doe (- z (* era 146097)))
         (yoe (/ (- doe (/ doe 1460) (- (/ doe 36524)) (/ doe 146096)) 365))
         (doy (- doe (- (+ (* 365 yoe) (/ yoe 4)) (/ yoe 100))))
         (mp (/ (+ (* 5 doy) 2) 153))
         (d (1+ (- doy (/ (+ (* 153 mp) 2) 5))))
         (m (if (< mp 10) (+ mp 3) (- mp 9)))
         (y (+ yoe (* era 400) (if (<= m 2) 1 0))))
    (format "%04d-%02d-%02d" y m d)))

(defun health-chart-format-date (date &optional format)
  "DATE (\"YYYY-MM-DD\") in FORMAT (default `health-chart-date-format')."
  (if (not (health-chart-date-p date))
      (format "%s" date)
    (let ((y (substring date 0 4)) (m (substring date 5 7)) (d (substring date 8 10)))
      (replace-regexp-in-string
       "%[Ymdyb%]"
       (lambda (spec)
         (pcase spec
           ("%Y" y) ("%m" m) ("%d" d) ("%y" (substring y 2))
           ("%b" (aref ["Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug"
                        "Sep" "Oct" "Nov" "Dec"]
                       (1- (string-to-number m))))
           (_ "%")))
       (or format health-chart-date-format) t t))))

;; -----------------------------------------------------------------------
;; Numbers
;; -----------------------------------------------------------------------

(defun health-chart-fmt (v)
  "V formatted compactly: integers bare, else up to two decimals.
Values below 1 keep three significant digits, so 0.004 stays 0.004."
  (cond
   ((not (numberp v)) (format "%s" (or v "")))
   ((integerp v) (number-to-string v))
   ((= v (ftruncate v)) (format "%d" (truncate v)))
   ((>= (abs v) 100) (format "%.0f" v))
   (t (let ((s (if (< (abs v) 1) (format "%.3g" v) (format "%.2f" v))))
        (setq s (if (string-search "." s) (replace-regexp-in-string "\\.?0+\\'" "" s) s))
        (if (equal s "-0") "0" s)))))

(defun health-chart-fmt-range (low high)
  "A human range for LOW and HIGH, either possibly nil, e.g. \"0–100\", \"≤70\"."
  (cond
   ((and low high) (format "%s–%s" (health-chart-fmt low) (health-chart-fmt high)))
   (high (format "≤%s" (health-chart-fmt high)))
   (low (format "≥%s" (health-chart-fmt low)))
   (t "")))

(defun health-chart-fmt-value (m)
  "Measurement M's value with its unit, e.g. \"112 mg/dL\"."
  (string-trim (format "%s %s" (health-chart-fmt (plist-get m :value))
                       (or (plist-get m :unit) ""))))

(defun health-chart-nice-ticks (lo hi count)
  "About COUNT round tick values covering LO..HI, ascending."
  (if (>= lo hi)
      (list lo)
    (let* ((raw (/ (- hi lo) (float (max 1 (1- count)))))
           (mag (expt 10.0 (floor (log raw 10))))
           (norm (/ raw mag))
           (step (* mag (cond ((< norm 1.5) 1) ((< norm 3) 2) ((< norm 7) 5) (t 10))))
           (start (* step (ceiling (/ lo step))))
           ticks)
      (cl-loop for v = start then (+ v step)
               while (<= v (+ hi (* step 1e-9)))
               do (push (/ (round (* v 1e6)) 1e6) ticks))
      (nreverse ticks))))

;; -----------------------------------------------------------------------
;; Status of a measurement
;; -----------------------------------------------------------------------

(defun health-chart--outside (v low high)
  "How far V lies outside LOW..HIGH (either possibly nil); 0 when inside."
  (max 0 (if low (- low v) 0) (if high (- v high) 0)))

(defun health-chart-status (m)
  "Status of measurement M: optimal, normal, suboptimal, low, high or unknown.
Reference bounds decide low/high; inside them, the optimal bounds (when
present) decide optimal versus suboptimal.  With no ranges at all the
source's :flag is trusted."
  (let ((v (plist-get m :value))
        (rl (plist-get m :ref-low)) (rh (plist-get m :ref-high))
        (ol (plist-get m :opt-low)) (oh (plist-get m :opt-high)))
    (cond
     ((not (numberp v)) 'unknown)
     ((and rl (< v rl)) 'low)
     ((and rh (> v rh)) 'high)
     ((or ol oh) (if (zerop (health-chart--outside v ol oh)) 'optimal 'suboptimal))
     ((or rl rh) 'normal)
     (t (pcase (plist-get m :flag)
          ((or 'high 'h 'critical_high 'critical-high) 'high)
          ((or 'low 'l 'critical_low 'critical-low) 'low)
          ((or 'normal 'ok 'in_range 'in-range) 'normal)
          ('optimal 'optimal)
          ('suboptimal 'suboptimal)
          (_ 'unknown))))))

(defun health-chart-out-of-range-p (m)
  "Non-nil when measurement M is outside its reference range."
  (memq (health-chart-status m) '(low high)))

;; -----------------------------------------------------------------------
;; Collections of measurements
;; -----------------------------------------------------------------------

(defun health-chart-sort-by-date (ms)
  "MS sorted oldest first (stable, so same-day draws keep their order)."
  (seq-sort-by (lambda (m) (plist-get m :date)) #'string< ms))

(defun health-chart-distinct (key ms)
  "Distinct non-nil KEY values of MS, in first-appearance order."
  (let (seen)
    (dolist (m ms) (let ((v (plist-get m key)))
                     (when (and v (not (member v seen))) (push v seen))))
    (nreverse seen)))

(defun health-chart-markers (ms)
  "Distinct markers of MS, in first-appearance order."
  (health-chart-distinct :marker ms))

(defun health-chart-persons (ms)
  "Distinct persons of MS, in first-appearance order."
  (health-chart-distinct :person ms))

(defun health-chart-dates (ms)
  "Distinct draw dates of MS, oldest first."
  (sort (health-chart-distinct :date ms) #'string<))

(defun health-chart-marker-key (marker)
  "MARKER folded for comparison: lower case, letters and digits only.
Sources spell one marker differently (biomarker-cli's \"ldl-c\" and
\"hscrp\", this package's \"ldl_c\" and \"hs_crp\"); they share a key."
  (when marker
    (replace-regexp-in-string "[^a-z0-9]" "" (downcase (format "%s" marker)))))

(defun health-chart-marker-equal (a b)
  "Non-nil when markers A and B name the same marker."
  (and a b (equal (health-chart-marker-key a) (health-chart-marker-key b))))

(cl-defun health-chart-filter (ms &key person marker category since until)
  "MS restricted to PERSON, MARKER, CATEGORY and dates SINCE..UNTIL.
A nil criterion does not filter.  MARKER may be a list of markers;
markers match by `health-chart-marker-key'."
  (seq-filter
   (lambda (m)
     (and (or (null person) (equal person (plist-get m :person)))
          (or (null marker)
              (seq-some (lambda (c) (health-chart-marker-equal c (plist-get m :marker)))
                        (if (listp marker) marker (list marker))))
          (or (null category) (equal category (health-chart-marker-category m)))
          (or (null since) (not (string< (plist-get m :date) since)))
          (or (null until) (not (string< until (plist-get m :date))))))
   ms))

(defun health-chart-by-marker (ms)
  "MS grouped as ((MARKER . MEASUREMENTS) ...), markers in first-appearance order.
Each group's measurements are sorted oldest first."
  (mapcar (lambda (marker)
            (cons marker (health-chart-sort-by-date
                          (seq-filter (lambda (m) (equal marker (plist-get m :marker))) ms))))
          (health-chart-markers ms)))

(defun health-chart-latest (ms)
  "The most recent measurement per marker in MS, in first-appearance order."
  (mapcar (lambda (group) (car (last (cdr group)))) (health-chart-by-marker ms)))

(defun health-chart-fill-ranges (ms)
  "MS with each range-less measurement given its marker's ranges.
A draw that carries no bounds at all takes those of the latest draw of
the same marker that does (see `health-chart-ranges'), so its status,
bands and table row agree.  Draws with any bound are left alone."
  (let ((cache (make-hash-table :test #'equal)))
    (mapcar
     (lambda (m)
       (if (or (plist-get m :ref-low) (plist-get m :ref-high)
               (plist-get m :opt-low) (plist-get m :opt-high))
           m
         (let ((ranges (or (gethash (plist-get m :marker) cache)
                           (puthash (plist-get m :marker)
                                    (health-chart-ranges
                                     (health-chart-filter ms :marker (plist-get m :marker)))
                                    cache))))
           (if (cl-some #'identity (cl-loop for (_ v) on ranges by #'cddr collect v))
               (append (cl-loop for (k v) on m by #'cddr
                                append (list k (if (plist-member ranges k) (plist-get ranges k) v)))
                       nil)
             m))))
     ms)))

(defun health-chart-ranges (ms)
  "Reference and optimal bounds for one marker's MS: the latest draw's.
A plist (:ref-low :ref-high :opt-low :opt-high); labs revise ranges, and
the newest is what the latest value is judged against."
  (let ((m (car (last (health-chart-sort-by-date
                       (seq-filter (lambda (m)
                                     (or (plist-get m :ref-low) (plist-get m :ref-high)
                                         (plist-get m :opt-low) (plist-get m :opt-high)))
                                   ms))))))
    (list :ref-low (plist-get m :ref-low) :ref-high (plist-get m :ref-high)
          :opt-low (plist-get m :opt-low) :opt-high (plist-get m :opt-high))))

;; -----------------------------------------------------------------------
;; Text helpers
;; -----------------------------------------------------------------------

(defun health-chart-pad (s width &optional right)
  "S truncated or padded with spaces to exactly WIDTH columns.
RIGHT non-nil right-aligns."
  (let* ((s (truncate-string-to-width (or s "") width nil nil "…"))
         (pad (make-string (max 0 (- width (string-width s))) ?\s)))
    (if right (concat pad s) (concat s pad))))

(defun health-chart--vec (list)
  "LIST as a vector, so `json-encode' emits an array, never an object."
  (apply #'vector list))

(provide 'health-chart-core)
;;; health-chart-core.el ends here
