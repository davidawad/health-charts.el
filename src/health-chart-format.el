;;; health-chart-format.el --- Display precision of values and labels -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Values arrive as computed floats (82.916685236 kg, a ratio of
;; 4.551020408) and every digit used to be drawn.  This file decides how
;; many to show.  It is display only: the numbers the status rule judges
;; stay as they came, the text goes into extra fields (`value_text' ...)
;; the templates draw.
;;
;; The rule, in `health-chart-format-number':
;;
;;   explicit decimals   a caller's DECIMALS (a binding, or a row's own
;;                       `decimals') is used as is: 82.9167 with 2 is
;;                       "82.92"
;;   otherwise           SIG significant figures (default 3, theme key
;;                       :sig-figs, slot `sig_figs') but never fewer
;;                       decimals than the row's reference limits show
;;                       (limits 0.0 and 0.2 keep one: 0.02 stays
;;                       "0.02"), and never a digit of the integer part
;;                       dropped (132 stays "132", 1234.5 is "1235").
;;                       Trailing zeros go, down to the limits' decimals.
;;
;; The long label column is cut the same way: `health-chart-format-truncate'
;; ends a label longer than the maximum (theme key :label-max, slot
;; `label_max') with an ellipsis.
;;
;; Registered with eas as the transform "health-format".

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'eas)

(defconst health-chart-format--max-decimals 6
  "The most decimals a limit can ask for, so a noisy limit does not widen a column.")

(defun health-chart-format--num (x)
  "X when it is a finite number, else nil."
  (and (numberp x) (or (integerp x) (and (not (isnan x)) (< (abs x) 1.0e+INF))) x))

(defun health-chart-format--printf (x decimals)
  "X as fixed-point text with DECIMALS decimals (`format' has no `*' width)."
  (format (format "%%.%df" decimals) x))

(defun health-chart-format-decimals-of (x)
  "The decimals X has when written as short as it can be, at most six.
0.2 has one, 132 none, 0.30000000000000004 one."
  (if (and (health-chart-format--num x) (floatp x))
      (let ((s (health-chart-format--printf x health-chart-format--max-decimals)))
        (if (string-match "\\.\\([0-9]*?\\)0*\\'" s)
            (length (match-string 1 s))
          0))
    0))

(defun health-chart-format--fixed (x decimals)
  "X with exactly DECIMALS decimals, never \"-0\" or \"-0.0\"."
  (let ((s (health-chart-format--printf x decimals)))
    (if (string-match-p "\\`-0\\(\\.0*\\)?\\'" s) (substring s 1) s)))

(defun health-chart-format--strip (s floor)
  "S without trailing zeros of its fraction, keeping at least FLOOR decimals."
  (if (string-match "\\`\\(-?[0-9]+\\)\\.\\([0-9]+\\)\\'" s)
      (let ((whole (match-string 1 s)) (frac (match-string 2 s)))
        (while (and (> (length frac) floor) (string-suffix-p "0" frac))
          (setq frac (substring frac 0 -1)))
        (if (string-empty-p frac) whole (concat whole "." frac)))
    s))

(cl-defun health-chart-format-number (n &key decimals (sig 3) limits)
  "N as display text.
DECIMALS, when a number, is used exactly.  Otherwise N gets SIG
significant figures (default 3) but at least as many decimals as the
numbers in LIMITS (a list) show, and its whole part is never cut.
Anything that is not a finite number comes back as the empty string."
  (let ((n (health-chart-format--num n)))
    (cond
     ((null n) "")
     ((and (numberp decimals) (>= decimals 0))
      (health-chart-format--fixed n (floor decimals)))
     (t
      (let* ((floor-d (apply #'max 0 (mapcar #'health-chart-format-decimals-of
                                             (seq-filter #'health-chart-format--num limits))))
             (sig (max 1 (floor (or (and (numberp sig) sig) 3))))
             (mag (if (zerop n) 0 (floor (log (abs (float n)) 10))))
             (sig-d (max 0 (- sig 1 mag)))
             (d (min health-chart-format--max-decimals (max floor-d sig-d))))
        (health-chart-format--strip (health-chart-format--fixed n d) floor-d))))))

(defun health-chart-format-truncate (text max)
  "TEXT cut to at most MAX characters, ending in an ellipsis when it was longer.
MAX nil or below 2 leaves TEXT alone."
  (if (and (stringp text) (natnump max) (>= max 2) (> (length text) max))
      (concat (string-trim-right (substring text 0 (1- max))) "…")
    text))

;;; The eas transform

(defconst health-chart-format--default-limit-fields
  '("ref_low" "ref_high" "goal" "low" "high")
  "Row fields whose decimals set the floor of a row's displayed decimals.")

(defun health-chart-format--field-names (v)
  "V (a vector or list of strings, or one string) as a list of strings."
  (cond ((stringp v) (list v))
        ((or (vectorp v) (listp v)) (seq-filter #'stringp (append v nil)))))

(defun health-chart-format--shared-limits (params)
  "The limits every row shares: PARAMS' :limit_values and the edges of its :bands."
  (let ((bands (plist-get params :bands)))
    (append (seq-filter #'health-chart-format--num (append (plist-get params :limit_values) nil))
            (cl-loop for band across (if (vectorp bands) bands [])
                     append (seq-filter #'health-chart-format--num
                                        (list (plist-get band :low) (plist-get band :high)))))))

(defun health-chart-format--labels (rows field max)
  "ROWS' FIELD values cut to MAX, as an alist of full label to shown label.
A label whose cut collides with another label's keeps its full text, so
two analytes are never merged into one row by the cut."
  (let* ((full (seq-uniq (seq-filter #'stringp
                                     (mapcar (lambda (r) (plist-get r (eas-key field)))
                                             (append rows nil)))))
         (cut (mapcar (lambda (s) (cons s (health-chart-format-truncate s max))) full)))
    (mapcar (lambda (e)
              (if (> (seq-count (lambda (o) (equal (cdr o) (cdr e))) cut) 1)
                  (cons (car e) (car e))
                e))
            cut)))

(defun health-chart-format--transform (rows params)
  "Add display text to ROWS; PARAMS are those of the registered transform."
  (let* ((fields (health-chart-format--field-names (plist-get params :fields)))
         (limit-fields (or (health-chart-format--field-names (plist-get params :limit_fields))
                           health-chart-format--default-limit-fields))
         (shared (health-chart-format--shared-limits params))
         (decimals (and (numberp (plist-get params :decimals)) (plist-get params :decimals)))
         (sig (plist-get params :sig))
         (label (plist-get params :label_field))
         (label-as (or (plist-get params :label_as) (and label (concat label "_short"))))
         (labels (and label (health-chart-format--labels rows label (plist-get params :label_max)))))
    (seq-into
     (seq-map
      (lambda (row)
        (let* ((own (plist-get row :decimals))
               (d (if (health-chart-format--num own) own decimals))
               (limits (append shared
                               (mapcar (lambda (f) (plist-get row (eas-key f))) limit-fields)))
               (out (cl-loop for f in fields
                             for v = (plist-get row (eas-key f))
                             when (health-chart-format--num v)
                             append (list (eas-key (concat f "_text"))
                                          (health-chart-format-number
                                           v :decimals d :sig sig :limits limits)))))
          (append (cl-loop for (k v) on row by #'cddr
                           unless (plist-member out k) append (list k v))
                  out
                  (and label (stringp (plist-get row (eas-key label)))
                       (list (eas-key label-as)
                             (cdr (assoc (plist-get row (eas-key label)) labels)))))))
      rows)
     'vector)))

(eas-register-transform
 "health-format"
 :doc "Add display text for numbers and labels, leaving the numbers alone: for each of FIELDS a field NAME_text with SIG significant figures (default 3) but never fewer decimals than the row's reference limits show, or exactly DECIMALS (a row's own decimals field wins).  LABEL_FIELD is also copied to LABEL_AS (default NAME_short) cut to LABEL_MAX characters with an ellipsis."
 :schema '(:fields (:type "array" :required t :doc "numeric fields to format; each adds NAME_text")
           :limit_fields (:type "array" :doc "row fields whose decimals set the least decimals shown (default ref_low, ref_high, goal, low, high)")
           :limit_values (:type "array" :doc "numbers every row's decimals must also cover, e.g. a constant range")
           :bands (:type "array" :doc "category bands {low, high} whose edges also set the least decimals")
           :decimals (:type "number" :doc "exact decimals of every NAME_text")
           :sig (:type "number" :doc "significant figures when decimals is not given")
           :label_field (:type "string" :doc "a text field to cut for display")
           :label_as (:type "string" :doc "the field the cut label is written to")
           :label_max (:type "number" :doc "the most characters a cut label keeps, ellipsis included"))
 :fn #'health-chart-format--transform)

;;; A derived value

(defun health-chart-format--divide (rows params)
  "Add AS to ROWS: NUMERATOR divided by DIVISOR to the POWER (default 2).
PARAMS carry :numerator, :divisor, :power and :as."
  (let* ((num (plist-get params :numerator))
         (divisor (plist-get params :divisor))
         (power (or (plist-get params :power) 2))
         (as (eas-key (or (plist-get params :as) "value")))
         (denominator (and (health-chart-format--num divisor) (expt divisor power))))
    (seq-into
     (seq-map (lambda (row)
                (let ((n (plist-get row (eas-key num))))
                  (if (and (health-chart-format--num n) denominator (not (zerop denominator)))
                      (append (cl-loop for (k v) on row by #'cddr unless (eq k as) append (list k v))
                              (list as (/ (float n) denominator)))
                    row)))
              rows)
     'vector)))

(eas-register-transform
 "health-divide"
 :doc "Add AS (default value) to each row: NUMERATOR divided by DIVISOR to the POWER (default 2), so a BMI is weight_kg over height_m squared.  A domain transform, so it runs before the native ones."
 :schema '(:numerator (:type "string" :required t :doc "the numeric field to divide")
           :divisor (:type "number" :required t :doc "what it is divided by, to the power")
           :power (:type "number" :default 2 :doc "the exponent of the divisor")
           :as (:type "string" :default "value" :doc "the field written"))
 :fn #'health-chart-format--divide)

(provide 'health-chart-format)
;;; health-chart-format.el ends here
