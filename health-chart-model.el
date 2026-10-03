;;; health-chart-model.el --- Backend-neutral chart models for health-chart -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Each chart kind first turns canonical measurements into a MODEL --
;; what to draw, already selected, sorted, scaled and judged -- and only
;; then hands it to the text or SVG renderer.  Both backends read the
;; same model, so they can never disagree about which marker, which
;; dates, which range or which status.  Models are plain plists, handy
;; for tests and for `health-chart-explain'.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'health-chart-core)

(defun health-chart-model--bands (ranges props)
  "The (:ref (LO . HI) :opt (LO . HI)) bands RANGES yields under PROPS.
A band is nil when hidden (:ref / :optimal props, defaulting to
`health-chart-show-ref-range' / `-optimal-range') or unbounded."
  (let ((show-ref (if (plist-member props :ref) (plist-get props :ref)
                    health-chart-show-ref-range))
        (show-opt (if (plist-member props :optimal) (plist-get props :optimal)
                    health-chart-show-optimal-range))
        (rl (plist-get ranges :ref-low)) (rh (plist-get ranges :ref-high))
        (ol (plist-get ranges :opt-low)) (oh (plist-get ranges :opt-high)))
    (list :ref (and show-ref (or rl rh) (cons rl rh))
          :opt (and show-opt (or ol oh) (cons ol oh)))))

(defun health-chart-model--y-range (values bands)
  "(LO . HI) for VALUES, stretched to show nearby BANDS edges, padded."
  (let* ((lo (apply #'min values)) (hi (apply #'max values))
         (reach (max (- hi lo) (* 0.1 (max (abs hi) (abs lo))) 1e-6))
         (edges (delq nil (list (car (plist-get bands :ref)) (cdr (plist-get bands :ref))
                                (car (plist-get bands :opt)) (cdr (plist-get bands :opt))))))
    (dolist (e edges)
      (when (and (>= e (- lo reach)) (<= e (+ hi reach)))
        (setq lo (min lo e) hi (max hi e))))
    (let ((pad (* 0.08 (max (- hi lo) (* 0.1 (max (abs hi) 1e-6))))))
      (cons (- lo pad) (+ hi pad)))))

(defun health-chart-model--pick (ms key props)
  "The value of KEY to chart: PROPS' KEY, else the first in MS."
  (or (plist-get props key) (car (health-chart-distinct key ms))))

(defun health-chart-model-series (ms &rest props)
  "Model for one marker over time from canonical MS.
PROPS: :marker (default the first in MS), :person (default the first),
:compare (non-nil: one line per person, ignoring :person), :ref,
:optimal.  Returns (:marker :label :unit :person :lines :ref :opt
:latest :x-range :y-range); each line is (:name NAME :points ((DAYS
VALUE MEASUREMENT) ...)) oldest first."
  (setq ms (health-chart-fill-ranges ms))
  (let* ((marker (health-chart-model--pick ms :marker props))
         (of-marker (health-chart-filter ms :marker marker))
         (compare (plist-get props :compare))
         (person (unless compare (health-chart-model--pick of-marker :person props)))
         (chosen (health-chart-sort-by-date
                  (seq-filter (lambda (m) (numberp (plist-get m :value)))
                              (if compare of-marker
                                (health-chart-filter of-marker :person person)))))
         (names (if compare (or (health-chart-persons chosen) '(nil)) (list person)))
         (lines (mapcar (lambda (name)
                          (list :name name
                                :points (mapcar (lambda (m)
                                                  (list (health-chart-date-days (plist-get m :date))
                                                        (plist-get m :value) m))
                                                (if compare
                                                    (seq-filter (lambda (m) (equal name (plist-get m :person)))
                                                                chosen)
                                                  chosen))))
                        names))
         (bands (health-chart-model--bands (health-chart-ranges chosen) props))
         (days (mapcar (lambda (m) (health-chart-date-days (plist-get m :date))) chosen))
         (values (mapcar (lambda (m) (plist-get m :value)) chosen)))
    (when chosen
      (append (list :marker marker :label (health-chart-marker-label marker)
                    :unit (plist-get (car (last chosen)) :unit)
                    :person (if compare nil person) :compare (and compare t)
                    :lines lines :latest (car (last chosen))
                    :x-range (cons (apply #'min days) (apply #'max days))
                    :y-range (health-chart-model--y-range values bands))
              bands))))

(defun health-chart-model-panel (ms &rest props)
  "Small-multiples model: one series model per marker of MS.
PROPS as in `health-chart-model-series' (:marker may be a list)."
  (let* ((person (health-chart-model--pick ms :person props))
         (mine (health-chart-filter ms :person person :marker (plist-get props :marker))))
    (delq nil (mapcar (lambda (marker)
                        (apply #'health-chart-model-series mine :marker marker
                               :person person props))
                      (health-chart-markers mine)))))

(defun health-chart-model-table (ms &rest props)
  "Sparkline-table rows for MS: one per marker of PROPS' :person.
Each row is (:marker :label :unit :latest :values :status :ref :opt)."
  (setq ms (health-chart-fill-ranges ms))
  (let ((person (health-chart-model--pick ms :person props)))
    (mapcar (lambda (group)
              (let* ((series (cdr group))
                     (latest (car (last series)))
                     (ranges (health-chart-ranges series)))
                (list :marker (car group) :label (health-chart-marker-label (car group))
                      :unit (plist-get latest :unit) :person person :latest latest
                      :values (delq nil (mapcar (lambda (m) (plist-get m :value)) series))
                      :status (health-chart-status latest)
                      :ref (health-chart-fmt-range (plist-get ranges :ref-low)
                                                   (plist-get ranges :ref-high))
                      :opt (health-chart-fmt-range (plist-get ranges :opt-low)
                                                   (plist-get ranges :opt-high)))))
            (health-chart-by-marker (health-chart-filter ms :person person
                                                         :marker (plist-get props :marker))))))

(defun health-chart-model-bullet (ms &rest props)
  "Range-bar rows for MS: where each marker's latest value sits.
PROPS as in `health-chart-model-table', plus :ref and :optimal.
Each row is (:marker :label :unit :value :latest :status :domain (LO .
HI) :ref :opt), bands as in `health-chart-model-series'."
  (mapcar
   (lambda (row)
     (let* ((latest (plist-get row :latest))
            (bands (health-chart-model--bands latest props))
            (v (plist-get latest :value))
            (finite (delq nil (list v (car (plist-get bands :ref)) (cdr (plist-get bands :ref))
                                    (car (plist-get bands :opt)) (cdr (plist-get bands :opt)))))
            (lo (apply #'min finite)) (hi (apply #'max finite))
            (pad (* 0.12 (max (- hi lo) (* 0.2 (abs v)) 1e-6))))
       (append (list :marker (plist-get row :marker) :label (plist-get row :label)
                     :unit (plist-get row :unit) :value v :latest latest
                     :status (plist-get row :status)
                     :domain (cons (if (and (>= lo 0) (< (- lo pad) 0)) 0 (- lo pad))
                                   (+ hi pad)))
               bands)))
   (apply #'health-chart-model-table ms props)))

(defun health-chart-model-heatmap (ms &rest props)
  "Out-of-range heatmap model for MS: markers by draw dates.
PROPS: :person :marker.
Returns (:person :dates :rows); each row (:marker :label :cells :out),
a cell being the measurement drawn that day or nil, :out the count of
out-of-range cells."
  (setq ms (health-chart-fill-ranges ms))
  (let* ((person (health-chart-model--pick ms :person props))
         (mine (health-chart-filter ms :person person :marker (plist-get props :marker)))
         (dates (health-chart-dates mine)))
    (list :person person :dates dates
          :rows (mapcar (lambda (group)
                          (let ((cells (mapcar (lambda (d)
                                                 (car (last (health-chart-filter (cdr group) :since d :until d))))
                                               dates)))
                            (list :marker (car group) :label (health-chart-marker-label (car group))
                                  :cells cells
                                  :out (seq-count (lambda (c) (and c (health-chart-out-of-range-p c)))
                                                  cells))))
                        (health-chart-by-marker mine)))))

(defun health-chart-model--verdict (before after)
  "Return improved, worsened, on-target, steady or nil: AFTER versus BEFORE.
The verdict compares how far each lies from target: on-target when both
are inside it, steady when equally far outside, nil with no ranges.
The target is the optimal range when AFTER has one, else the reference."
  (let* ((ranges (health-chart-ranges (list before after)))
         (opt (or (plist-get ranges :opt-low) (plist-get ranges :opt-high)))
         (lo (plist-get ranges (if opt :opt-low :ref-low)))
         (hi (plist-get ranges (if opt :opt-high :ref-high))))
    (when (or lo hi)
      (let ((db (health-chart--outside (plist-get before :value) lo hi))
            (da (health-chart--outside (plist-get after :value) lo hi))
            (eps (* 1e-9 (max 1 (abs (plist-get after :value))))))
        (cond ((< da (- db eps)) 'improved)
              ((> da (+ db eps)) 'worsened)
              ((zerop da) 'on-target)
              (t 'steady))))))

(defun health-chart-model-delta (ms &rest props)
  "Change model between two draws of MS.
PROPS: :person, :from and :to dates (default the two latest draw dates).
Returns (:person :from :to :rows); a row is (:marker :label :unit :before
:after :change :pct :verdict).  Markers missing either draw are left out."
  (setq ms (health-chart-fill-ranges ms))
  (let* ((person (health-chart-model--pick ms :person props))
         (mine (health-chart-filter ms :person person :marker (plist-get props :marker)))
         (dates (health-chart-dates mine))
         (to (or (plist-get props :to) (car (last dates))))
         (from (or (plist-get props :from)
                   (car (last (seq-filter (lambda (d) (string< d to)) dates))))))
    (list :person person :from from :to to
          :rows (when (and from to)
                  (delq nil
                        (mapcar
                         (lambda (group)
                           (let ((b (car (last (health-chart-filter (cdr group) :since from :until from))))
                                 (a (car (last (health-chart-filter (cdr group) :since to :until to)))))
                             (when (and b a)
                               (let ((bv (plist-get b :value)) (av (plist-get a :value)))
                                 (list :marker (car group) :label (health-chart-marker-label (car group))
                                       :unit (plist-get a :unit) :before bv :after av
                                       :change (- av bv)
                                       :pct (if (zerop bv) nil (* 100.0 (/ (- av bv) (float (abs bv)))))
                                       :verdict (health-chart-model--verdict b a))))))
                         (health-chart-by-marker mine)))))))

(defun health-chart-model-resample (values width)
  "VALUES averaged into at most WIDTH buckets (unchanged when shorter)."
  (let ((n (length values)))
    (if (<= n width)
        values
      (let ((per (/ (float n) width)))
        (cl-loop for i from 0 below width
                 for start = (floor (* i per))
                 for end = (max (1+ start) (floor (* (1+ i) per)))
                 for group = (cl-subseq values start (min end n))
                 collect (/ (apply #'+ group) (float (length group))))))))

(provide 'health-chart-model)
;;; health-chart-model.el ends here
