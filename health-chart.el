;;; health-chart.el --- Biomarker charts: text in a terminal, SVG in a GUI -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; Maintainer: David Awad <me@davidaw.ad>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: data, tools
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;; Permission is hereby granted, free of charge, to any person obtaining a
;; copy of this software, to deal in it without restriction (MIT licence).

;;; Commentary:

;; Lab results in, chart out.  One call draws any biomarker chart kind --
;; a marker's time series with reference and optimal ranges shaded,
;; small multiples, a sparkline table, range ("bullet") bars, an
;; out-of-range heatmap, a multi-person overlay, change bars between two
;; draws -- as propertized unicode text in a terminal or an SVG image in
;; a GUI.  Data comes from plain Lisp (plists or alists) or from the
;; biomarker CLI through the swappable `health-chart-source' layer.
;;
;; The central object is a CHART SPEC, a plist that round-trips JSON:
;;
;;   (:kind timeseries :data MEASUREMENTS :marker "ldl_c" :backend text)
;;
;; and every entry point takes the same pieces:
;;
;;   discover   `health-chart-list-kinds', `health-chart-describe-kind',
;;              `health-chart-describe' (the whole package as data)
;;   validate   `health-chart-validate' -> t or a typed error with :index
;;   plan       `health-chart-explain' -> backend + why, renderer, args,
;;              data summary; pure, never renders
;;   render     `health-chart-plot' (string), `-plot-insert' (at point),
;;              `-plot-view' (buffer), `-plot-spec' (from a spec)
;;   fetch      `health-chart-source-query', `-trend', `-latest', `-flag'
;;   dashboard  `health-charts' (M-x), alias of `health-chart-dashboard'
;;   health     `health-chart-doctor' (M-x) / `health-chart-doctor-checks'
;;
;; Non-Emacs callers use bin/health-chart, which reads a spec as JSON.
;; Modules: -core (config, dates, status), -source (biomarker data
;; layer), -model (what to draw), -text, -svg, -plot (kinds), -dashboard,
;; -batch (CLI).

;;; Code:

(require 'cl-lib)
(require 'health-chart-core)
(require 'health-chart-source)
(require 'health-chart-model)
(require 'health-chart-text)
(require 'health-chart-svg)
(require 'health-chart-plot)
(require 'health-chart-dashboard)

(defconst health-chart-version "0.1.0"
  "Version of the health-chart package.")

(defconst health-chart-entry-points
  '((discover health-chart-list-kinds health-chart-describe-kind health-chart-describe)
    (validate health-chart-validate)
    (plan health-chart-explain)
    (render health-chart-plot health-chart-plot-spec health-chart-plot-insert
            health-chart-plot-view health-chart-sparkline health-chart-demo)
    (fetch health-chart-source-query health-chart-source-trend health-chart-source-latest
           health-chart-source-flag health-chart-source-normalize-list)
    (dashboard health-charts health-chart-dashboard)
    (extend health-chart-register-kind health-chart-shapes health-chart-source-function)
    (health health-chart-doctor health-chart-doctor-checks))
  "Public entry points grouped by what a caller is doing.")

;;;###autoload
(defun health-chart-describe ()
  "Describe the whole package as data.
Version, kinds, shapes, statuses, source and entry points.  Lists are
vectors, so the result round-trips `json-encode'."
  (list :package "health-chart" :version health-chart-version
        :kinds (health-chart--vec
                (mapcar (lambda (k)
                          (list :kind (symbol-name (car k))
                                :shape (symbol-name (plist-get (cdr k) :shape))
                                :doc (plist-get (cdr k) :doc)))
                        (health-chart-list-kinds)))
        :shapes (health-chart--vec
                 (mapcar (lambda (s) (list :shape (symbol-name (car s))
                                           :doc (plist-get (cdr s) :doc)))
                         health-chart-shapes))
        :statuses (health-chart--vec (mapcar #'symbol-name health-chart-statuses))
        :source (list :function (format "%s" health-chart-source-function)
                      :executable health-chart-source-executable
                      :schema health-chart-source-schema
                      :commands (health-chart--vec (mapcar #'symbol-name
                                                           health-chart-source-commands)))
        :entry-points (health-chart--vec
                       (mapcar (lambda (g)
                                 (list :verb (symbol-name (car g))
                                       :functions (health-chart--vec
                                                   (mapcar #'symbol-name (cdr g)))))
                               health-chart-entry-points))))

;;;###autoload
(defun health-chart-doctor-checks ()
  "Every package health row: (:name :status :detail :remediation).
:status is pass, fail or skip.  Covers chart kinds and the data source;
runs no process."
  (append (health-chart-plot-doctor-checks)
          (health-chart-source-doctor-checks)))

;;;###autoload
(defun health-chart-doctor ()
  "Show `health-chart-doctor-checks' in a buffer; return the rows."
  (interactive)
  (let ((rows (health-chart-doctor-checks)))
    (with-current-buffer (get-buffer-create "*health-chart doctor*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "health-chart %s\n\n" health-chart-version))
        (dolist (r rows)
          (insert (format "%-5s %s -- %s\n" (upcase (symbol-name (plist-get r :status)))
                          (plist-get r :name) (plist-get r :detail)))
          (when (plist-get r :remediation)
            (insert (format "      fix: %s\n" (plist-get r :remediation))))))
      (special-mode)
      (unless noninteractive (pop-to-buffer (current-buffer))))
    rows))

(provide 'health-chart)
;;; health-chart.el ends here
