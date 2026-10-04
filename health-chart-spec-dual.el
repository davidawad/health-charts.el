;;; health-chart-spec-dual.el --- Spec body of the dual chart kind -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Two markers on one time axis with independent y scales.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'health-chart-core)
(require 'health-chart-model)
(require 'health-chart-spec)

;; -----------------------------------------------------------------------
;; dual: two markers, two axes
;; -----------------------------------------------------------------------

(defun health-chart-spec-gallery--dual-markers (ms props)
  "The two marker names a dual chart draws, from MS and PROPS.
PROPS' :marker list, else glucose and HbA1c when present, else the first
two markers of MS."
  (let ((picked (plist-get props :marker)))
    (cond ((and (listp picked) (cdr picked)) (seq-take picked 2))
          (t (let ((all (health-chart-markers ms)))
               (if (and (member "glucose" all) (member "hba1c" all)) '("glucose" "hba1c")
                 (seq-take all 2)))))))

(defun health-chart--check-dual (data props)
  "Signal unless a dual chart can pick two markers of DATA under PROPS."
  (let* ((picked (plist-get props :marker))
         (present (health-chart-markers data))
         (two (health-chart-spec-gallery--dual-markers data props)))
    (when (or (< (length two) 2)
              (and picked (listp picked) (/= (length picked) 2)))
      (signal 'health-chart-invalid-data
              (list (format ":marker must name two markers for a dual-axis chart; markers present: %s"
                            (string-join present ", "))
                    :code "invalid_prop")))
    (dolist (m two)
      (unless (member m present)
        (signal 'health-chart-invalid-data
                (list (format "no measurements for marker %S; markers present: %s" m
                              (string-join present ", "))
                      :code "unknown_marker" :marker m))))))

(defun health-chart-spec-dual (ms props)
  "Spec body overlaying two markers of MS on a left and a right axis, under PROPS."
  (let* ((theme (health-chart-spec--theme props))
         (names (health-chart-spec-gallery--dual-markers ms props))
         (person (health-chart-model--pick ms :person props))
         (palette (or (alist-get 'series health-chart-colors)
                      (alist-get 'series (health-chart-spec--palette theme))))
         (inks (list (nth 0 palette) (nth (min 6 (1- (length palette))) palette)))
         (models (mapcar (lambda (name)
                           (apply #'health-chart-model-series ms :marker name :person person
                                  (health-chart--plist-drop props :marker :person)))
                         names)))
    (when (and (= 2 (length models)) (cl-every #'identity models))
      (let* ((sides '("left" "right"))
             (series
              (cl-loop for model in models for side in sides for ink in inks
                       for range = (health-chart-spec--floor-zero
                                    (plist-get model :y-range)
                                    (mapcar #'cadr (plist-get (car (plist-get model :lines)) :points)))
                       for latest = (plist-get model :latest)
                       collect (list :name (plist-get model :marker) :axis side
                                     :label (format "%s (%s axis)" (plist-get model :label) side)
                                     :title (if (string-empty-p (or (plist-get model :unit) ""))
                                                (plist-get model :label)
                                              (format "%s (%s)" (plist-get model :label)
                                                      (plist-get model :unit)))
                                     :unit (plist-get model :unit)
                                     :color ink :rgb (health-chart-spec--rgb ink)
                                     :domain (vector (health-chart-spec--round (car range))
                                                     (health-chart-spec--round (cdr range)))
                                     :latest_label (format "%s %s  %s" (plist-get model :label)
                                                           (health-chart-fmt-value latest)
                                                           (health-chart-status-label
                                                            (health-chart-status latest))))))
             (rows (cl-loop
                    for model in models for s in series
                    append (let* ((pts (plist-get (car (plist-get model :lines)) :points))
                                  (n (length pts)))
                             (cl-loop for p in pts for i from 1
                                      collect (health-chart-spec--row
                                               (cl-third p) theme ms
                                               :series (plist-get s :name)
                                               :series_label (plist-get s :label)
                                               :series_color (plist-get s :color)
                                               :axis (plist-get s :axis)
                                               :latest (if (= i n) 1 0))))))
             (chosen (mapcar (lambda (r) (list :date (plist-get r :date))) rows))
             (thresholds
              (apply #'vector
                     (delq nil
                           (cl-loop for model in models for s in series
                                    collect
                                    (let* ((target (or (plist-get model :ref) (plist-get model :opt)))
                                           (edge (or (cdr target) (car target))))
                                      (when edge
                                        (list :value edge :axis (plist-get s :axis)
                                              :label (format "%s %s%s" (plist-get model :label)
                                                             (if (cdr target) "≤" "≥")
                                                             (health-chart-fmt edge))
                                              :color (plist-get s :color))))))))
             (annotations
              (apply #'vector
                     (cl-loop for model in models for s in series
                              collect (append (plist-put
                                               (health-chart-spec--latest-annotation
                                                (plist-get model :latest) theme)
                                               :text (plist-get s :latest_label))
                                              (list :axis (plist-get s :axis)
                                                    :series (plist-get s :name)
                                                    :series_color (plist-get s :color)))))))
        (list :title (format "%s · %s · %s" (plist-get (nth 0 models) :label)
                             (plist-get (nth 1 models) :label) (or person "all"))
              :subtitle (concat "latest: " (string-join (mapcar (lambda (s) (plist-get s :latest_label)) series) " · "))
              :x (health-chart-spec--date-axis (health-chart-dates chosen) nil
                                               (health-chart-spec--width props))
              :y (health-chart-spec--value-axis nil nil)
              :layout (list :left (nth 0 series) :right (nth 1 series))
              :rows (apply #'vector rows)
              :overlays (health-chart-spec--overlays :thresholds thresholds :annotations annotations)
              :legend (health-chart-spec--status-legend
                       theme (mapcar (lambda (r) (intern (plist-get r :status))) rows))
              :series (apply #'vector series)
              :meta (health-chart-spec--meta
                     (apply #'append (mapcar (lambda (m) (mapcar #'cl-third (plist-get (car (plist-get m :lines)) :points)))
                                             models))))))))

(provide 'health-chart-spec-dual)
;;; health-chart-spec-dual.el ends here
