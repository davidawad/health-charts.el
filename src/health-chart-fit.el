;;; health-chart-fit.el --- Show only as many draws as a grid has room for -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A grid with a column per draw date squeezes its columns as draws
;; are added.  In a text view a column narrower than its cell text
;; (glyph, space, value) makes neighbouring cells overwrite each other
;; and the first one spill into the label column.  So a grid shows
;; its latest MAX_DRAWS draws:
;;
;;   a binding or slot   :max_draws N shows the latest N draw dates,
;;                       0 shows every date.
;;   no binding, text    the most draws whose columns still hold the
;;                       widest cell text plus one space, from the
;;                       view's width, the label column, and the legend.
;;   no binding, svg     the most draws whose columns still hold the
;;                       widest cell text at the value font size.
;;
;; The columns are the draw dates of the markers shown.  A marker drawn
;; far more often than the rest (weight or a wearable reading next to
;; a few lab draws) would bring its every date as a column and leave
;; the lab rows mostly empty, so by default it is left out: a marker
;; with more than `health-chart-fit-frequency-ratio' times the median
;; number of draw dates (and at least `health-chart-fit-frequency-gap'
;; more).  The slot include_frequent keeps them.
;;
;; `health-chart-fit-bindings' adds the slot and says so in the
;; subtitle; the cuts themselves are the eas transforms
;; "health-common-cadence" and "health-latest-draws".  A template opts
;; in with "fit": "draws" in its health block.  A live view
;; (`health-chart-fit-watch') is fitted again on every resize.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'eas)
(require 'eas-view)
(require 'health-chart-theme)
(require 'health-chart-status)
(require 'health-chart-format)

(defconst health-chart-fit--legend-gap 4
  "Cells a text legend takes beside its widest word: the offset and the swatch.")

(defun health-chart-fit--day (row field)
  "ROW's FIELD (an ISO date or date-time) cut to its date, or nil."
  (let ((v (plist-get row (eas-key field))))
    (and (stringp v) (>= (length v) 10) (substring v 0 10))))

(defun health-chart-fit-days (rows &optional field)
  "The distinct dates of ROWS' FIELD (default \"time\"), oldest first."
  (sort (seq-uniq (delq nil (mapcar (lambda (r) (health-chart-fit--day r (or field "time")))
                                    (append rows nil))))
        #'string<))

(defconst health-chart-fit-frequency-ratio 4
  "A marker with more than this times the median count of draw dates is frequent.")

(defconst health-chart-fit-frequency-gap 10
  "A frequent marker also has at least this many draw dates more than the median.")

(defun health-chart-fit--on (v)
  "Non-nil when V is a true slot value (not nil, :false or :null)."
  (not (memq v '(nil :false :null))))

(defun health-chart-fit-frequent (rows &optional analyte time)
  "The markers of ROWS drawn far more often than the rest, in order of appearance.
A marker's draws are its distinct dates of TIME (default \"time\"); it is
frequent when it has more than `health-chart-fit-frequency-ratio' times
the median count of its ANALYTE field (default \"analyte\") and at least
`health-chart-fit-frequency-gap' more."
  (let* ((akey (eas-key (or analyte "analyte")))
         (tfield (or time "time"))
         (dates (make-hash-table :test 'equal))
         (order nil))
    (dolist (r (append rows nil))
      (let ((a (plist-get r akey)) (d (health-chart-fit--day r tfield)))
        (when (and a d)
          (unless (gethash a dates) (push a order))
          (puthash a (cons d (gethash a dates)) dates))))
    (let* ((counts (mapcar (lambda (a) (cons a (length (seq-uniq (gethash a dates))))) (nreverse order)))
           (sorted (sort (mapcar #'cdr counts) #'<))
           (median (and sorted (nth (/ (1- (length sorted)) 2) sorted))))
      (and median
           (mapcar #'car
                   (seq-filter (lambda (c) (and (> (cdr c) (* health-chart-fit-frequency-ratio median))
                                                (>= (- (cdr c) median) health-chart-fit-frequency-gap)))
                               counts))))))

(defun health-chart-fit--common (rows params)
  "ROWS without those of frequent markers, unless PARAMS :include is true.
PARAMS :analyte and :time name the fields (`health-chart-fit-frequent')."
  (if (health-chart-fit--on (plist-get params :include))
      rows
    (let* ((akey (eas-key (or (plist-get params :analyte) "analyte")))
           (drop (health-chart-fit-frequent rows (plist-get params :analyte) (plist-get params :time))))
      (if (null drop)
          rows
        (seq-into (seq-remove (lambda (r) (member (plist-get r akey) drop)) (append rows nil))
                  'vector)))))

(eas-register-transform
 "health-common-cadence"
 :doc "Leave out the rows of markers drawn far more often than the rest (more than 4 times the median count of draw dates), unless INCLUDE.  A domain transform: it runs before the native ones."
 :schema '(:analyte (:type "string" :default "analyte" :doc "the field naming the marker")
           :time (:type "string" :default "time" :doc "the field holding an ISO date or date-time")
           :include (:type "boolean" :doc "keep every marker"))
 :fn #'health-chart-fit--common)

(defun health-chart-fit--latest (rows params)
  "ROWS of the latest PARAMS :max draw dates (all when :max is not positive)."
  (let* ((field (or (plist-get params :time) "time"))
         (max (plist-get params :max))
         (days (health-chart-fit-days rows field))
         (keep (and (natnump max) (> max 0) (< max (length days))
                    (last days max))))
    (if (null keep)
        rows
      (seq-into (seq-filter (lambda (r) (member (health-chart-fit--day r field) keep))
                            (append rows nil))
                'vector))))

(eas-register-transform
 "health-latest-draws"
 :doc "Keep only the rows of the latest MAX distinct dates of TIME (all rows when MAX is missing or 0).  A domain transform: it runs before the native ones."
 :schema '(:time (:type "string" :default "time" :doc "the field holding an ISO date or date-time")
           :max (:type "number" :doc "how many of the latest draw dates to keep; 0 or missing keeps all"))
 :fn #'health-chart-fit--latest)

(defun health-chart-fit--number (bindings key theme-key)
  "BINDINGS' numeric KEY, else the theme's THEME-KEY."
  (let ((v (plist-get bindings key)))
    (if (numberp v) v (health-chart-theme-get theme-key))))

(defun health-chart-fit-cell-width (rows bindings)
  "The widest cell text of ROWS in cells: a glyph, a space and the value text.
Values are formatted as the grid formats them (BINDINGS' :decimals and
:sig_figs, a row's own decimals, the digits its limits show)."
  (let ((decimals (and (numberp (plist-get bindings :decimals)) (plist-get bindings :decimals)))
        (sig (health-chart-fit--number bindings :sig_figs :sig-figs)))
    (+ 2 (apply #'max 1
                (mapcar
                 (lambda (r)
                   (let ((own (plist-get r :decimals)))
                     (string-width
                      (health-chart-format-number
                       (plist-get r :value)
                       :decimals (if (numberp own) own decimals) :sig sig
                       :limits (mapcar (lambda (k) (plist-get r k))
                                       '(:ref_low :ref_high :opt_low :opt_high))))))
                 (append rows nil))))))

(defun health-chart-fit-label-width (rows bindings)
  "Width of the widest row label of ROWS, cut to the label maximum.
BINDINGS may set :label_max."
  (let ((labels (health-chart-format--labels
                 rows "analyte" (health-chart-fit--number bindings :label_max :label-max))))
    (apply #'max 1 (mapcar (lambda (e) (string-width (or (cdr e) ""))) labels))))

(defun health-chart-fit-draws-for (rows bindings cols)
  "How many draw dates of ROWS fit COLS text columns, at least 1.
BINDINGS give the display precision.
The plot is what is left of COLS beside the label column (and its one
cell of gutter) and the legend; every column needs the widest cell text
plus one space."
  (let* ((legend (+ health-chart-fit--legend-gap
                    (apply #'max (mapcar (lambda (e) (string-width (cdr e)))
                                         health-chart-status-labels))))
         (plot (- cols (health-chart-fit-label-width rows bindings) 1 legend))
         (cell (1+ (health-chart-fit-cell-width rows bindings))))
    (max 1 (floor plot cell))))

(defun health-chart-fit-draws-for-pixels (rows bindings width)
  "How many draw dates of ROWS fit an SVG WIDTH pixels wide, at least 1.
BINDINGS give the display precision.  Like `health-chart-fit-draws-for'
with the label column, the legend and every column's widest cell text
measured in pixels at the axis and value font sizes."
  (let* ((labels (health-chart-format--labels
                  rows "analyte" (health-chart-fit--number bindings :label_max :label-max)))
         (label (+ 8 4 (apply #'max 1 (mapcar (lambda (e) (eas-font-text-width (or (cdr e) "") 10))
                                              labels))))
         (legend (+ 40 (apply #'max (mapcar (lambda (e) (eas-font-text-width (cdr e) 10))
                                            health-chart-status-labels))))
         (cell (+ 8 (eas-font-text-width
                     (make-string (health-chart-fit-cell-width rows bindings) ?0) 11))))
    (max 1 (floor (- width label legend 10) cell))))

(defun health-chart-fit--note (bindings notes room)
  "BINDINGS with NOTES after its subtitle.
A note is a string, or a list of a long and a short form.  The long
forms are used when the subtitle then fits ROOM characters (or ROOM is
nil), else the short ones."
  (let* ((sub (plist-get bindings :subtitle))
         (join (lambda (pick)
                 (string-join (append (and (stringp sub) (not (string-empty-p sub)) (list sub))
                                      (mapcar (lambda (n) (if (consp n) (funcall pick n) n)) notes))
                              "; ")))
         (long (funcall join #'car)))
    (plist-put (copy-sequence bindings) :subtitle
               (if (or (null room) (<= (string-width long) room)) long (funcall join #'cadr)))))

(defun health-chart-fit-bindings (template bindings backend cols)
  "BINDINGS of TEMPLATE with its draws fitted to a view COLS wide.
COLS is text columns for the text BACKEND and pixels for svg (nil: no
fit).  Only a template that declares \"fit\": \"draws\" in its health
block is touched.  Rows of frequent markers are left out unless
:include_frequent is true (`health-chart-fit-frequent'); the draws
counted are those of the markers shown.  A :max_draws binding is kept
as it is (0 shows every draw); without one as many draws as fit are
shown.  The subtitle says what is left out."
  (let ((health (plist-get (plist-get template :meta) :health)))
    (if (not (equal (plist-get health :fit) "draws"))
        bindings
      (let* ((all (plist-get bindings :data))
             (drop (and (not (health-chart-fit--on (plist-get bindings :include_frequent)))
                        (health-chart-fit-frequent all)))
             (rows (if drop (health-chart-fit--common all nil) all))
             (days (length (health-chart-fit-days rows)))
             (asked (plist-get bindings :max_draws))
             (shown (cond ((numberp asked) (if (> asked 0) asked days))
                          ((or (not (numberp cols)) (= days 0)) days)
                          ((eq backend 'text) (health-chart-fit-draws-for rows bindings cols))
                          (t (health-chart-fit-draws-for-pixels rows bindings cols))))
             (notes (append
                     (and drop
                          (list (list (format "not shown, drawn far more often: %s"
                                              (string-join drop ", "))
                                      (format "%d frequent marker%s not shown"
                                              (length drop) (if (cdr drop) "s" "")))))
                     (and (< shown days) (list (format "latest %d of %d draws" shown days)))))
             (out (if (< shown days) (plist-put (copy-sequence bindings) :max_draws shown) bindings)))
        (if (null notes)
            out
          (health-chart-fit--note out notes (and (numberp cols)
                                                 (if (eq backend 'text) (- cols 4) (floor cols 7)))))))))

;;; Live views

(defvar health-chart-fit--views (make-hash-table :test 'eq :weakness 'key)
  "Live views fitted on resize: view to (TEMPLATE . BINDINGS), as given.")

(defun health-chart-fit--refit (view size &optional target)
  "Re-resolve VIEW for SIZE and TARGET before `eas-view-resize' compiles it.
Only a view `health-chart-fit-watch' registered is touched, and only
when its fitted bindings change."
  (let* ((view (and (or (eas-view-p view) (stringp view)) (ignore-errors (eas-view-get view))))
         (entry (and view (gethash view health-chart-fit--views))))
    (when entry
      (let* ((target (or target (eas-view-target view)))
             (cols (if (eq target 'text) (plist-get size :cols) (car-safe size)))
             (bindings (health-chart-fit-bindings (car entry) (cdr entry) target cols)))
        (unless (equal bindings (eas-view-bindings view))
          (let ((spec (eas-resolve (plist-get (car entry) :name) bindings)))
            (setf (eas-view-bindings view) bindings
                  (eas-view-spec view) spec
                  (eas-view-spec-hash view) (eas-resolve-hash spec)
                  (eas-view-data view)
                  (eas-data-make (or (plist-get (plist-get spec :data) :values) []))
                  (eas-view-plan view) nil)))))))

(defun health-chart-fit-watch (view template bindings)
  "Fit VIEW, a live view of TEMPLATE from BINDINGS, again whenever it is resized.
Every `eas-view-resize' of VIEW (a window resized, split or switched,
`eas-show') then re-resolves it with `health-chart-fit-bindings' at the
new size.  Returns VIEW."
  (when (equal (plist-get (plist-get (plist-get template :meta) :health) :fit) "draws")
    (puthash view (cons template bindings) health-chart-fit--views)
    (advice-add 'eas-view-resize :before #'health-chart-fit--refit))
  view)

(provide 'health-chart-fit)
;;; health-chart-fit.el ends here
