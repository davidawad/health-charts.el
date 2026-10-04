;;; health-chart-kind.el --- Chart kinds, data shapes and validation -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; The registries every renderer and backend share: `health-chart-shapes'
;; (what data a kind accepts, how to normalize and validate it) and
;; `health-chart-kinds' (each kind's shape, native renderers and doc),
;; plus the synthetic example data and `health-chart-validate'.  Nothing
;; here draws.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'health-chart-core)
(require 'health-chart-source)
(require 'health-chart-indicator)

(defvar health-chart-backends)

;; -----------------------------------------------------------------------
;; Errors: (MESSAGE :code CODE ...), the message naming the fix.
;; -----------------------------------------------------------------------

(define-error 'health-chart-unknown-kind
  "health-chart: unknown chart kind" 'health-chart-error)
(define-error 'health-chart-invalid-data
  "health-chart: invalid chart data" 'health-chart-error)

(defun health-chart--invalid (index fmt &rest args)
  "Signal `health-chart-invalid-data' at element INDEX; FMT/ARGS the reason."
  (signal 'health-chart-invalid-data
          (list (format "element %d: %s" index (apply #'format fmt args))
                :code "invalid_data" :index index)))

;; -----------------------------------------------------------------------
;; Synthetic example data -- two made-up people, nine markers, six draws.
;; -----------------------------------------------------------------------

(defconst health-chart--example-dates
  '("2024-03-04" "2024-06-03" "2024-09-02" "2024-12-02" "2025-03-03" "2025-06-02")
  "Draw dates of the example data.")

(defconst health-chart--example-markers
  ;; marker unit ref-low ref-high opt-low opt-high  alex values  sam values
  '(("ldl_c" "mg/dL" 0 100 nil 70 (131 124 108 96 112 88) (92 95 88 84 79 74))
    ("hdl_c" "mg/dL" 40 nil 60 nil (52 55 58 57 54 61) (64 66 63 67 70 68))
    ("triglycerides" "mg/dL" 0 150 nil 100 (162 140 121 118 134 104) (88 92 81 79 85 76))
    ("apob" "mg/dL" 0 90 nil 80 (104 99 91 86 93 84) (71 73 69 66 64 62))
    ("glucose" "mg/dL" 70 99 72 90 (97 101 94 92 99 93) (86 84 88 85 83 87))
    ("hba1c" "%" nil 5.7 nil 5.3 (5.6 5.8 5.5 5.4 5.6 5.3) (5.1 5.0 5.2 5.1 5.0 5.1))
    ("vitamin_d" "ng/mL" 30 100 40 60 (24 31 38 45 36 48) (52 49 55 58 51 54))
    ("tsh" "mIU/L" 0.4 4.0 0.5 2.5 (1.9 2.2 2.0 2.6 2.4 2.1) (1.4 1.6 1.5 1.3 1.7 1.5))
    ("crp" "mg/L" nil 3.0 nil 1.0 (2.4 3.6 1.8 1.2 2.1 3.4) (0.6 0.5 0.9 0.4 0.7 0.5)))
  "Example markers: (MARKER UNIT REF-LOW REF-HIGH OPT-LOW OPT-HIGH ALEX SAM).")

(defun health-chart--example-measurements (&optional persons)
  "Synthetic canonical measurements for PERSONS (default both)."
  (let ((persons (or persons '("alex" "sam"))))
    (cl-loop
     for person in persons
     append (cl-loop
             for (marker unit rl rh ol oh alex sam) in health-chart--example-markers
             append (cl-loop for date in health-chart--example-dates
                             for v in (if (equal person "alex") alex sam)
                             collect (let ((m (list :person person :marker marker :value v
                                                    :unit unit :date date :ref-low rl
                                                    :ref-high rh :opt-low ol :opt-high oh)))
                                       (health-chart-source-normalize
                                        (plist-put m :flag (let ((s (health-chart-status m)))
                                                             (if (memq s '(low high)) s 'normal))))))))))

;; -----------------------------------------------------------------------
;; Shapes and kinds -- registries, so the whole surface is enumerable.
;; -----------------------------------------------------------------------

(defun health-chart--validate-measurements (data)
  "Signal unless DATA (already normalized) is a list of valid measurements."
  (unless (listp data)
    (signal 'health-chart-invalid-data
            (list (format "measurements must be a list, got %S" data) :code "invalid_data")))
  (cl-loop
   for m in data for i from 0
   do (let ((marker (plist-get m :marker)) (date (plist-get m :date)))
        (unless (and (stringp marker) (not (string-empty-p marker)))
          (health-chart--invalid i "needs a non-empty \"marker\", got %S" marker))
        (unless (health-chart-date-p date)
          (health-chart--invalid i "needs \"date\" as YYYY-MM-DD, got %S" date))
        (unless (numberp (plist-get m :value))
          (health-chart--invalid i "needs a numeric \"value\", got %S" (plist-get m :value)))
        (dolist (key '(:ref-low :ref-high :opt-low :opt-high))
          (let ((v (plist-get m key)))
            (unless (or (null v) (numberp v))
              (health-chart--invalid i "%s must be a number or null, got %S" key v))))
        (dolist (pair '((:ref-low . :ref-high) (:opt-low . :opt-high)))
          (let ((lo (plist-get m (car pair))) (hi (plist-get m (cdr pair))))
            (when (and lo hi (> lo hi))
              (health-chart--invalid i "%s %s exceeds %s %s (swap them)"
                                     (car pair) lo (cdr pair) hi)))))))

(defun health-chart--normalize-series (data)
  "DATA as a list of numbers, oldest first.
DATA is numbers in order, (DATE . VALUE) or (DATE VALUE) pairs, or the
measurements of one marker; pairs and measurements are sorted by date."
  (let ((items (append data nil)))
    (cond
     ((cl-every #'numberp items) items)
     ((cl-every (lambda (p) (and (consp p) (stringp (car p)))) items)
      (mapcar (lambda (p) (if (consp (cdr p)) (cadr p) (cdr p)))
              (seq-sort-by #'car #'string< items)))
     ((cl-every #'consp items)
      (let ((ms (health-chart-source-normalize-list items)))
        (when (cdr (health-chart-markers ms))
          (signal 'health-chart-invalid-data
                  (list (format "a sparkline shows one marker, got %s; filter with `health-chart-filter'"
                                (string-join (health-chart-markers ms) ", "))
                        :code "invalid_data")))
        (mapcar (lambda (m) (plist-get m :value)) (health-chart-sort-by-date ms))))
     (t items))))

(defun health-chart--validate-series (data)
  "Signal unless DATA (already normalized) is a list of numbers."
  (cl-loop for v in data for i from 0
           unless (numberp v)
           do (health-chart--invalid i "expected a number, got %S" v)))

;; Synthetic indicator values: alex's example draws through the local
;; evaluators, judged as of a fixed day so the example never changes.
(defconst health-chart--example-indicator-members
  '(("health.cardio.apob") ("health.cardio.lp-a")
    ("health.biomarker.latest" :marker "ldl_c")
    ("health.metabolic.hba1c")
    ("health.biomarker.trend-slope" :marker "glucose")
    ("health.inflammation.hs-crp")
    ("health.biomarker.range-position" :marker "crp")
    ("health.vitamin-d")
    ("health.panel.out-of-range-count"))
  "(RECIPE-ID . PARAMS) of the example indicator values.")

(defun health-chart--example-indicator-values ()
  "Synthetic canonical indicator values for alex, as of 2025-08-01."
  (let ((ms (health-chart--example-measurements '("alex"))))
    (mapcar (lambda (member)
              (apply #'health-chart-indicator-evaluate (car member) ms
                     :as-of "2025-08-01" :cohort "example" (cdr member)))
            health-chart--example-indicator-members)))

(defun health-chart--validate-indicators (data)
  "Signal `health-chart-invalid-data' unless DATA are valid indicator values."
  (condition-case err (health-chart-indicator-validate-values data)
    (health-chart-error (signal 'health-chart-invalid-data (cdr err)))))

(defvar health-chart-shapes
  `((measurements
     :doc "biomarker/v1 measurements: plists (:marker :date :value [:person :unit
:ref-low :ref-high :opt-low :opt-high :flag :category]), alists or JSON
objects with the same members (snake_case accepted), or a biomarker/v1
envelope {\"schema\":\"biomarker/v1\",\"measurements\":[...]}.  Any order."
     :example ,(health-chart--example-measurements)
     :normalize health-chart-source-normalize-list
     :validator health-chart--validate-measurements)
    (series
     :doc "Numbers oldest first, or (DATE . VALUE) pairs, or measurements."
     :example (131 124 108 96 112 88)
     :normalize health-chart--normalize-series
     :validator health-chart--validate-series)
    (indicators
     :doc "Indicator values: plists (:id :label :value [:unit :date :as-of :series
:direction :bounds :ref-low :ref-high :opt-low :opt-high :marker :person
:cohort :measure :status]), or alists / JSON objects with the same members
\(snake_case accepted).  :direction is lower-better, higher-better,
in-range or neutral; :bounds is (LO HI) or {\"min\":LO,\"max\":HI}.
`health-chart-indicator-evaluate' and `health-chart-cohort-values' make them."
     :example ,(health-chart--example-indicator-values)
     :normalize health-chart-indicator-normalize-values
     :validator health-chart--validate-indicators))
  "Data shapes: (SHAPE :doc :example :normalize FN :validator FN).
:normalize turns any accepted input into the canonical form (and must be
idempotent); :validator signals `health-chart-invalid-data' with :index.")

(defvar health-chart-kinds
  '((timeseries :shape measurements :spec health-chart-spec-timeseries :text health-chart-text-timeseries
                :svg health-chart-svg-timeseries :check health-chart--check-one-marker
                :doc "One marker over time with reference and optimal bands shaded.")
    (panel :shape measurements :spec health-chart-spec-panel :text health-chart-text-panel :svg health-chart-svg-panel
           :doc "Small multiples: a compact time series per marker (a panel dashboard).")
    (table :shape measurements :text health-chart-text-table :svg health-chart-svg-table
           :doc "Sparkline table: marker | latest | trend | flag | reference.")
    (bullet :shape measurements :spec health-chart-spec-bullet :text health-chart-text-bullet :svg health-chart-svg-bullet
            :doc "Range bars: where each marker's latest value sits in its ranges.")
    (heatmap :shape measurements :spec health-chart-spec-heatmap :text health-chart-text-heatmap :svg health-chart-svg-heatmap
             :doc "Markers by draw dates, each cell the draw's status (out-of-range map).")
    (compare :shape measurements :spec health-chart-spec-compare :text health-chart-text-compare :svg health-chart-svg-compare
             :check health-chart--check-one-marker
             :doc "One marker over time for several people, overlaid.")
    (delta :shape measurements :spec health-chart-spec-delta :text health-chart-text-delta :svg health-chart-svg-delta
           :check health-chart--check-delta
           :doc "Percent change per marker between two draws, toward or away from target.")
    (trend :shape measurements :spec health-chart-spec-trend
           :check health-chart--check-one-marker
           :doc "One marker's draws with a 3-draw rolling mean and a linear trend, slope in words.")
    (lollipop :shape measurements :spec health-chart-spec-lollipop
              :check health-chart--check-one-marker
              :doc "One marker's draws as stems to its target limit: how far past it each draw was.")
    (strip :shape measurements :spec health-chart-spec-strip
           :doc "Every draw of every marker on its own range scale (0 = reference low, 1 = high).")
    (dumbbell :shape measurements :spec health-chart-spec-dumbbell
              :doc "First draw to latest draw per marker on its range scale, colored by verdict.")
    (dual :shape measurements :spec health-chart-spec-dual
          :check health-chart--check-dual
          :doc "Two related markers (glucose and HbA1c) over time on a left and a right axis.")
    (inrange :shape measurements :spec health-chart-spec-inrange
             :doc "Share of each marker's draws below, inside and above its reference range.")
    (sparkline :shape series :text health-chart-text-sparkline :svg health-chart-svg-sparkline
               :doc "One-row sparkline of plain numbers, for tables and mode lines.")
    (scorecard :shape indicators :text health-chart-text-scorecard :svg health-chart-svg-scorecard
               :doc "Indicator scorecard: indicator | value | unit | status | trend sparkline.")
    (cohort :shape indicators :text health-chart-text-cohort :svg health-chart-svg-cohort
            :doc "Cohort panel: a card per indicator with value, status, range track and trend.")
    (staleness :shape indicators :spec health-chart-spec-staleness :text health-chart-text-staleness :svg health-chart-svg-staleness
               :check health-chart--check-staleness
               :doc "Days since each indicator's draw, against due and stale thresholds."))
  "Chart kinds: (KIND :shape SHAPE :text FN :svg FN :doc DOC [:check FN]).
:spec FN is optional too.  A kind with neither :text nor :svg (trend,
lollipop, strip, dumbbell, dual, inrange) is drawn by templates only:
the native backends skip it, auto selection picks a template backend.
Renderers are called as (FN DATA &rest PROPS) with normalized DATA and
return a string, or nil when there is nothing to draw.  :check (DATA
PROPS) validates props that select from DATA.  :spec (DATA PROPS) builds
the kind's chartspec/v1 body for template backends (health-chart-spec.el);
without it a generic body is used.")

(defun health-chart--check-one-marker (data props)
  "Signal unless PROPS' :marker, when given, occurs in DATA."
  (when-let* ((marker (plist-get props :marker)))
    (unless (member marker (health-chart-markers data))
      (signal 'health-chart-invalid-data
              (list (format "no measurements for marker %S; markers present: %s" marker
                            (string-join (health-chart-markers data) ", "))
                    :code "unknown_marker" :marker marker)))))

(defun health-chart--check-delta (data props)
  "Signal unless PROPS' :from and :to, when given, are draw dates in DATA."
  (dolist (key '(:from :to))
    (when-let* ((d (plist-get props key)))
      (unless (member d (health-chart-dates data))
        (signal 'health-chart-invalid-data
                (list (format "%s %S is not a draw date; dates present: %s" key d
                              (string-join (health-chart-dates data) ", "))
                      :code "unknown_date" :date d))))))

(defun health-chart--check-staleness (_data props)
  "Signal unless PROPS' :as-of is a date and :due-days / :stale-days numbers."
  (when-let* ((d (plist-get props :as-of)))
    (unless (health-chart-date-p d)
      (signal 'health-chart-invalid-data
              (list (format ":as-of must be YYYY-MM-DD, got %S" d) :code "invalid_prop"))))
  (dolist (key '(:due-days :stale-days))
    (when-let* ((n (plist-get props key)))
      (unless (natnump n)
        (signal 'health-chart-invalid-data
                (list (format "%s must be a whole number of days, got %S" key n)
                      :code "invalid_prop"))))))

(defun health-chart-register-kind (kind &rest spec)
  "Register (or replace) chart KIND with SPEC (:shape :text :svg :doc [:check]).
:shape must name an entry of `health-chart-shapes'."
  (unless (assq (plist-get spec :shape) health-chart-shapes)
    (signal 'health-chart-error
            (list (format "unknown shape %S; known: %S" (plist-get spec :shape)
                          (mapcar #'car health-chart-shapes))
                  :code "unknown_shape")))
  (setf (alist-get kind health-chart-kinds) spec)
  kind)

(defvar health-chart-kind-fallback-functions nil
  "Functions of KIND returning a registry plist for a kind not registered.
The first non-nil answer wins; health-chart-render adds one that admits
kinds known only by a template file.")

(defun health-chart--kind (kind)
  "KIND's registry plist, or signal `health-chart-unknown-kind'."
  (or (alist-get kind health-chart-kinds)
      (run-hook-with-args-until-success 'health-chart-kind-fallback-functions kind)
      (signal 'health-chart-unknown-kind
              (list (format "%S is not a chart kind; use one of %s (see `health-chart-list-kinds')"
                            kind (mapconcat #'symbol-name (mapcar #'car health-chart-kinds) ", "))
                    :code "unknown_kind" :kind kind))))

(defun health-chart--shape (kind)
  "The shape plist of KIND."
  (alist-get (plist-get (health-chart--kind kind) :shape) health-chart-shapes))

(defcustom health-chart-series-categories '("body" "vitals")
  "Categories of frequently measured series (daily weight, heart rate...).
Draw-based kinds (`health-chart-draw-kinds') leave these markers out
when lab markers are present, so a year of daily weigh-ins does not turn
into hundreds of \"draws\".  nil keeps every marker."
  :type '(repeat string)
  :group 'health-charts)

(defconst health-chart-draw-kinds '(heatmap delta inrange dumbbell strip)
  "Kinds organised by lab draw date.")

(defun health-chart--drop-series (kind data)
  "DATA without `health-chart-series-categories' markers when KIND is a draw kind.
Unchanged for other kinds, when DATA is not a measurement list, or when
nothing but series markers would remain."
  (if (and (memq kind health-chart-draw-kinds) health-chart-series-categories
           (proper-list-p data) (cl-every (lambda (m) (and (listp m) (plist-member m :marker))) data))
      (let ((labs (seq-remove (lambda (m) (member (health-chart-marker-category m)
                                                  health-chart-series-categories))
                              data)))
        (if labs labs data))
    data))

(defun health-chart-normalize (kind data)
  "DATA in KIND's canonical form (see `health-chart-shapes').
Draw-based kinds also drop daily series (`health-chart-series-categories')."
  (health-chart--drop-series kind (health-chart--normalize-shape kind data)))

(defun health-chart--normalize-shape (kind data)
  "DATA in KIND's canonical form, as KIND's shape normalizes it."
  (if-let* ((fn (plist-get (health-chart--shape kind) :normalize)))
      (condition-case err (funcall fn data)
        (health-chart-source-error (signal (car err) (cdr err)))
        (health-chart-error
         (signal 'health-chart-invalid-data (list (cadr err) :code "invalid_data")))
        (wrong-type-argument
         (signal 'health-chart-invalid-data
                 (list (format "cannot read data as %s: %S" (plist-get (health-chart--kind kind) :shape)
                               err)
                       :code "invalid_data"))))
    data))

;;;###autoload
(defun health-chart-validate (kind data &rest props)
  "Return t when DATA fits KIND's shape and PROPS, else signal a typed error.
`health-chart-invalid-data' carries the offending element's :index.
Empty DATA is valid: it renders as nothing."
  (let* ((entry (health-chart--kind kind))
         (data (health-chart-normalize kind data))
         (backend (plist-get props :backend)))
    (unless (or (memq backend '(nil auto text svg))
                (and (boundp 'health-chart-backends) (assq backend health-chart-backends)))
      (signal 'health-chart-invalid-data
              (list (format ":backend must be auto or one of %s, got %S"
                            (mapconcat #'symbol-name
                                       (if (boundp 'health-chart-backends)
                                           (mapcar #'car health-chart-backends)
                                         '(text svg))
                                       ", ")
                            backend)
                    :code "invalid_prop")))
    (when data
      (funcall (plist-get (health-chart--shape kind) :validator) data)
      (when-let* ((check (plist-get entry :check)))
        (funcall check data props)))
    t))

(defun health-chart--plist-drop (plist &rest keys)
  "PLIST without KEYS."
  (cl-loop for (k v) on plist by #'cddr
           unless (memq k keys) append (list k v)))

(provide 'health-chart-kind)
;;; health-chart-kind.el ends here
