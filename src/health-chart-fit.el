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
;;   no binding, svg     every draw (columns are pixels wide and the
;;                       view scrolls or scales).
;;
;; `health-chart-fit-bindings' adds the slot and says so in the
;; subtitle; the cut itself is the eas transform "health-latest-draws".
;; A template opts in with "fit": "draws" in its health block.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'eas)
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

(defun health-chart-fit-bindings (template bindings backend cols)
  "BINDINGS of TEMPLATE with its draws fitted to a view of COLS text columns.
Only a template that declares \"fit\": \"draws\" in its health block is
touched.  A :max_draws binding is kept as it is (0 shows every draw);
without one the text BACKEND gets as many draws as fit.  When draws are
left out the subtitle says how many are shown."
  (let ((health (plist-get (plist-get template :meta) :health)))
    (if (not (equal (plist-get health :fit) "draws"))
        bindings
      (let* ((rows (plist-get bindings :data))
             (days (length (health-chart-fit-days rows)))
             (asked (plist-get bindings :max_draws))
             (shown (cond ((numberp asked) (if (> asked 0) asked days))
                          ((and (eq backend 'text) (> days 0))
                           (health-chart-fit-draws-for rows bindings cols))
                          (t days))))
        (if (>= shown days)
            bindings
          (let* ((out (plist-put (copy-sequence bindings) :max_draws shown))
                 (note (format "latest %d of %d draws" shown days))
                 (sub (plist-get bindings :subtitle)))
            (plist-put out :subtitle (if (and (stringp sub) (not (string-empty-p sub)))
                                         (concat sub "; " note)
                                       note))))))))

(provide 'health-chart-fit)
;;; health-chart-fit.el ends here
