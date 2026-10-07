;;; health-chart-eas.el --- health-chart templates and transforms on eas -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; The eas half of health-chart.  Through eas's public registries only,
;; it adds the template directory under the namespace "health"
;; (templates/lab-trend.json is the template "health/lab-trend").
;; eas never refers to health-chart; dependencies point this way.

;;; Code:

(require 'eas)

(defconst health-chart-eas--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "The health-chart repository root.")

(defun health-chart-eas-template-directory ()
  "The directory holding health-chart's eas templates."
  (expand-file-name "templates" health-chart-eas--root))

(eas-template-add-directory (health-chart-eas-template-directory) "health")

(require 'health-chart-transforms)

(provide 'health-chart-eas)
;;; health-chart-eas.el ends here
