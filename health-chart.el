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
;;   indicators `health-chart-indicator-list' / `-describe' (catalog),
;;              `health-chart-list-cohorts', `health-chart-describe-cohort',
;;              `health-chart-cohort-values', `health-chart-cohort-plot';
;;              each effectful call has a pure `-explain' twin
;;   dashboard  `health-charts' (M-x), alias of `health-chart-dashboard'
;;   reports    Org dynamic blocks (#+BEGIN: health-chart, health-table,
;;              health-scorecard, health-flags, health-genetics,
;;              health-genetics-labs) and
;;              report templates: `health-chart-org-new-report',
;;              `health-chart-org-update', `health-chart-org-templates';
;;              plans from `health-chart-org-explain'
;;   health     `health-chart-doctor' (M-x) / `health-chart-doctor-checks'
;;
;; Non-Emacs callers use bin/health-chart, which reads a spec as JSON.
;; Modules: -core (config, dates, status), -source (biomarker data
;; layer), -indicator (catalog, indicator values, evaluators), -model
;; (what to draw), -text, -svg, -plot (kinds), -cohort (named indicator
;; sets), -dashboard, -batch (CLI), -org (Org reports; loaded on
;; first use, so plain charts never load Org).

;;; Code:

(require 'cl-lib)
(require 'health-chart-core)
(require 'health-chart-source)
(require 'health-chart-model)
(require 'health-chart-text)
(require 'health-chart-svg)
(require 'health-chart-indicator)
(require 'health-chart-kind)
(require 'health-chart-spec)
(require 'health-chart-template)
(require 'health-chart-render)
(require 'health-chart-plot)
(require 'health-chart-cohort)
(require 'health-chart-dashboard)
(require 'health-chart-genetics)

;; The Org report layer loads on first use (it requires Org).
(dolist (fn '(health-chart-org-new-report health-chart-org-update health-chart-org-templates))
  (autoload fn "health-chart-org" nil t))
(dolist (fn '(health-chart-org-explain health-chart-org-new-report-explain
              health-chart-org-stamp health-chart-org-context health-chart-org-template-list
              org-dblock-write:health-chart org-dblock-write:health-table
              org-dblock-write:health-scorecard org-dblock-write:health-flags
              org-dblock-write:health-genetics org-dblock-write:health-genetics-labs))
  (autoload fn "health-chart-org"))

(defconst health-chart-version "0.2.0"
  "Version of the health-chart package.")

(defconst health-chart-entry-points
  '((discover health-chart-list-kinds health-chart-describe-kind health-chart-describe
              health-chart-list-cohorts health-chart-describe-cohort
              health-chart-indicator-list health-chart-indicator-describe
              health-chart-templates)
    (validate health-chart-validate health-chart-resolve-cohort)
    (plan health-chart-explain health-chart-render-explain health-chart-spec
          health-chart-indicator-list-explain
          health-chart-indicator-describe-explain health-chart-describe-cohort-explain
          health-chart-cohort-values-explain health-chart-cohort-plot-explain)
    (render health-chart-render health-chart-write health-chart-plot
            health-chart-plot-spec health-chart-plot-insert
            health-chart-plot-view health-chart-sparkline health-chart-demo
            health-chart-cohort-plot health-chart-cohort-view)
    (fetch health-chart-source-query health-chart-source-trend health-chart-source-latest
           health-chart-source-flag health-chart-source-normalize-list
           health-chart-cohort-values health-chart-indicator-catalog-get)
    (evaluate health-chart-indicator-evaluate health-chart-cohort-evaluate
              health-chart-indicator-status)
    (dashboard health-charts health-chart-dashboard)
    (report health-chart-org-new-report health-chart-org-update health-chart-org-templates
            health-chart-org-explain health-chart-org-new-report-explain
            health-chart-org-stamp health-chart-org-template-list)
    (genetics health-chart-gene-lab-links health-chart-genetics-links
              health-chart-genetics-calls health-chart-genetics-calls-explain
              health-chart-genetics-functions)
    (extend health-chart-register-kind health-chart-shapes health-chart-backends
            health-chart-template-directories health-chart-source-function
            health-chart-indicator-catalog-function health-chart-indicator-cohorts
            health-chart-indicator-evaluators health-chart-indicator-measures)
    (health health-chart-doctor health-chart-doctor-checks))
  "Public entry points grouped by what a caller is doing.")

;;;###autoload
(defun health-chart-describe ()
  "Describe the whole package as data.
Version, kinds, shapes, statuses, backends, templates, indicators,
cohorts, source and entry points.  Lists are
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
        :spec-schema health-chart-spec-schema
        :backend (symbol-name health-chart-backend)
        :backends (health-chart--vec
                   (mapcar (lambda (b)
                             (list :backend (symbol-name (car b))
                                   :doc (plist-get (cdr b) :doc)
                                   :formats (health-chart--vec
                                             (mapcar #'symbol-name (plist-get (cdr b) :formats)))
                                   :available (if (health-chart-backend-available-p (car b)) t
                                                :json-false)
                                   :obsolete (if (plist-get (cdr b) :obsolete) t :json-false)))
                           health-chart-backends))
        :templates (health-chart--vec
                    (mapcar (lambda (tpl)
                              (list :backend (symbol-name (plist-get tpl :backend))
                                    :kind (symbol-name (plist-get tpl :kind))
                                    :path (plist-get tpl :path)
                                    :source (symbol-name (plist-get tpl :source))))
                            (health-chart-templates)))
        :indicators (list :catalog (format "%s" health-chart-indicator-catalog-function)
                          :tag health-chart-indicator-tag
                          :evaluable (health-chart--vec (health-chart-indicator-known-ids))
                          :measures (health-chart--vec
                                     (mapcar (lambda (m) (list :measure (symbol-name (car m))
                                                               :doc (plist-get (cdr m) :doc)))
                                             health-chart-indicator-measures))
                          :directions (health-chart--vec (mapcar #'symbol-name
                                                                 health-chart-indicator-directions)))
        :cohorts (health-chart--vec
                  (mapcar (lambda (c)
                            (list :cohort (symbol-name (car c)) :doc (plist-get (cdr c) :doc)
                                  :members (plist-get (cdr c) :members)
                                  :resolvable (plist-get (cdr c) :resolvable)))
                          (health-chart-list-cohorts)))
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
:status is pass, fail or skip.  Covers chart kinds, rendering backends
and templates, the data source, the indicator catalog and cohorts; runs
no process and calls no catalog."
  (append (health-chart-plot-doctor-checks)
          (health-chart-render-doctor-checks)
          (health-chart-source-doctor-checks)
          (health-chart-cohort-doctor-checks)
          (health-chart-genetics-doctor-checks)))

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
