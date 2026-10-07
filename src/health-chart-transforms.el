;;; health-chart-transforms.el --- Domain transforms for health-chart templates -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Transforms registered with eas, through its public registry only.
;; They do arithmetic on rows the caller supplied; nothing is fetched.
;;
;;   "time-of-day-percentiles"  folds readings taken on many days onto
;;       one 24 hour day: rows are grouped into buckets of BUCKET_MINUTES
;;       by their clock time and each bucket becomes one row
;;       {tod, p5, p25, p50, p75, p95, n}.  TOD is the bucket's start in
;;       hours (0 to 24).  Percentiles interpolate linearly between the
;;       ranked values (the "inclusive" method).  This is the shape of an
;;       ambulatory glucose profile (AGP).

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'eas)

(defun health-chart-transforms--percentile (sorted p)
  "Percentile P (0 to 100) of SORTED, a vector of numbers, by interpolation."
  (let* ((n (length sorted))
         (rank (* (/ p 100.0) (1- n)))
         (lo (floor rank))
         (hi (min (1- n) (1+ lo)))
         (frac (- rank lo)))
    (+ (aref sorted lo) (* frac (- (aref sorted hi) (aref sorted lo))))))

(defun health-chart-transforms--clock-minutes (time)
  "Minutes since midnight of the ISO date-time string TIME, or nil without a clock."
  (when (and (stringp time)
             (string-match "[T ]\\([0-9]\\{2\\}\\):\\([0-9]\\{2\\}\\)" time))
    (+ (* 60 (string-to-number (match-string 1 time)))
       (string-to-number (match-string 2 time)))))

(defun health-chart-transforms--round (x)
  "X rounded to two decimals."
  (/ (fround (* x 100.0)) 100.0))

(defun health-chart-transforms--time-of-day-percentiles (rows params)
  "Fold ROWS onto one day and return percentile rows; PARAMS as documented above."
  (let* ((field (eas-key (or (plist-get params :field) "glucose")))
         (time-key (eas-key (or (plist-get params :time) "time")))
         (width (or (plist-get params :bucket_minutes) 30))
         (buckets (make-hash-table :test #'eql)))
    (unless (and (integerp width) (> width 0) (<= width 1440) (zerop (% 1440 width)))
      (eas-signal "INVALID_INPUT"
                  (format "bucket_minutes must divide 1440 (for example 15, 30 or 60), got %S" width)
                  :transform "time-of-day-percentiles" :field "bucket_minutes"))
    (seq-doseq (row rows)
      (let ((minutes (health-chart-transforms--clock-minutes (plist-get row time-key)))
            (value (plist-get row field)))
        (unless minutes
          (eas-signal "INVALID_INPUT"
                      (format "Row time %S has no clock time; give ISO date-times such as 2026-03-01T08:30"
                              (plist-get row time-key))
                      :transform "time-of-day-percentiles" :field (eas-key-name time-key)))
        (when (numberp value)
          (push value (gethash (* width (/ minutes width)) buckets)))))
    (let (out)
      (maphash
       (lambda (start values)
         (let ((sorted (vconcat (sort (copy-sequence values) #'<))))
           (push (list :tod (health-chart-transforms--round (/ start 60.0))
                       :p5 (health-chart-transforms--round (health-chart-transforms--percentile sorted 5))
                       :p25 (health-chart-transforms--round (health-chart-transforms--percentile sorted 25))
                       :p50 (health-chart-transforms--round (health-chart-transforms--percentile sorted 50))
                       :p75 (health-chart-transforms--round (health-chart-transforms--percentile sorted 75))
                       :p95 (health-chart-transforms--round (health-chart-transforms--percentile sorted 95))
                       :n (length values))
                 out)))
       buckets)
      (vconcat (sort out (lambda (a b) (< (plist-get a :tod) (plist-get b :tod))))))))

(eas-register-transform
 "time-of-day-percentiles"
 :doc "Fold readings from many days onto one day: per time-of-day bucket, the 5th, 25th, 50th, 75th and 95th percentile of FIELD (rows {tod, p5, p25, p50, p75, p95, n})."
 :schema '(:field (:type "string" :default "glucose" :doc "the numeric column to summarize")
           :time (:type "string" :default "time" :doc "the ISO date-time column")
           :bucket_minutes (:type "integer" :default 30 :doc "bucket width in minutes; must divide 1440"))
 :fn #'health-chart-transforms--time-of-day-percentiles)

(provide 'health-chart-transforms)
;;; health-chart-transforms.el ends here
