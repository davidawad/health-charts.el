;;; health-chart-org.el --- Org reports: dynamic blocks and report templates -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; The composition layer: health reports as plain Org files.
;;
;; Dynamic blocks (refresh one with C-c C-c on its #+BEGIN line, all
;; with `health-chart-org-update' or `org-update-all-dblocks'):
;;
;;   #+BEGIN: health-chart :kind timeseries :person "alex" :marker "ldl-c"
;;   #+END:
;;       writes the chart with `health-chart-write' into the document's
;;       asset directory (`health-chart-org-asset-directory') under a
;;       stable name derived from the params, and inserts the
;;       [[file:...]] link (with #+CAPTION from :caption).  A kind no
;;       image template draws becomes a text chart in an example block.
;;   health-table      the latest values as an Org table, with a #+PLOT
;;                     line so org-plot can chart it too
;;   health-scorecard  a cohort's indicator values with status and trend
;;   health-flags      the markers out of range, as a list
;;   health-genetics   genetics.el's own blocks, when genetics.el is loaded
;;   health-genetics-labs  per gene in `health-chart-gene-lab-links': the
;;                     genotype from genetics.el (when loaded), then the
;;                     linked markers' latest values and a small chart each
;;
;; Params: :person :marker :markers :category :cohort :since :until
;; :as-of select the data; :kind :backend :format :width :height :title
;; :columns :baseline :file :caption shape the chart.  Each block has a
;; pure explain twin (`health-chart-org-chart-explain' and friends,
;; `health-chart-org-explain' by block name) giving the data query and
;; output path.  A failing block writes one Org comment line carrying
;; the error's runbook message; the document never breaks.
;;
;; Report templates are Org files in templates/org/ (user directories in
;; `health-chart-org-template-directories' first) with {{person}},
;; {{date}}, {{since}}, {{until}}, {{period}} and {{year}} placeholders,
;; the syntax of the chart templates.  `health-chart-org-new-report'
;; stamps one, refreshes its blocks and opens it.
;;
;; Export: HTML shows the SVG charts inline; LaTeX/PDF export re-runs
;; the chart blocks in the export copy as PNG
;; (`health-chart-org-latex-png').

;;; Code:

(require 'org)
(require 'health-chart-org-base)
(require 'health-chart-org-explain)
(require 'health-chart-org-blocks)
(require 'health-chart-org-genetics-labs)
(require 'health-chart-org-report)

;;;###autoload
(defun org-dblock-write:health-chart (params)
  "Org dynamic block: a health chart image for PARAMS.
See `health-chart-org-chart-explain' for the plan."
  (health-chart-org--guard "health-chart" (health-chart-org--chart params)))

;;;###autoload
(defun org-dblock-write:health-table (params)
  "Org dynamic block: the latest values for PARAMS as a table.
See `health-chart-org-table-explain' for the plan."
  (health-chart-org--guard "health-table" (health-chart-org--table params)))

;;;###autoload
(defun org-dblock-write:health-scorecard (params)
  "Org dynamic block: a cohort scorecard table for PARAMS.
See `health-chart-org-scorecard-explain' for the plan."
  (health-chart-org--guard "health-scorecard" (health-chart-org--scorecard params)))

;;;###autoload
(defun org-dblock-write:health-flags (params)
  "Org dynamic block: out-of-range markers for PARAMS as a list.
See `health-chart-org-flags-explain' for the plan."
  (health-chart-org--guard "health-flags" (health-chart-org--flags params)))

;;;###autoload
(defun org-dblock-write:health-genetics (params)
  "Org dynamic block: genetics.el's section for PARAMS, when it is loaded.
Never loads genetics.el; without it, writes a one-line note.  See
`health-chart-org-genetics-explain' for the plan."
  (health-chart-org--prefer-utf-8)
  (let ((plan (health-chart-org-genetics-explain params)))
    (cond
     ((not (eq (plist-get plan :valid) t))
      (insert (format "# health-genetics (%s): %s" (or (plist-get plan :code) "invalid_param")
                     (plist-get plan :valid))))
     ((plist-get plan :available)
      (condition-case err
          (funcall (plist-get plan :delegate) (plist-get plan :args))
        (error (insert (health-chart-org--error-line "health-genetics" err)))))
     (t (insert (format "/Genetics %s: genetics.el is not loaded; load it and refresh this block./"
                        (plist-get plan :section)))))))

;;;###autoload
(defun org-dblock-write:health-genetics-labs (params)
  "Org dynamic block: each linked gene's call and lab markers for PARAMS.
Genotypes come from genetics.el when it is loaded (never loaded from
here); without it, or without a call at a gene, a one-line note takes
their place.  Always ends with the informational-only line.  See
`health-chart-org-genetics-labs-explain' for the plan."
  (health-chart-org--guard "health-genetics-labs" (health-chart-org--genetics-labs params)))

;; -----------------------------------------------------------------------
;; Refresh and export
;; -----------------------------------------------------------------------

(defconst health-chart-org--block-regexp
  "^[ \t]*#\\+BEGIN:[ \t]+\\(health-\\(?:chart\\|table\\|scorecard\\|flags\\|genetics\\|genetics-labs\\)\\)\\_>"
  "A health dynamic block's first line.")

(defun health-chart-org--update-blocks (&optional only)
  "Refresh the buffer's health blocks (those named ONLY, when given); count them."
  (let ((n 0) (case-fold-search t))
    (save-excursion
      (org-with-wide-buffer
       (goto-char (point-min))
       (while (re-search-forward health-chart-org--block-regexp nil t)
         (when (or (null only) (member (downcase (match-string 1)) only))
           (goto-char (match-beginning 0))
           (org-update-dblock)
           (setq n (1+ n)))
         (forward-line 1))))
    n))

;;;###autoload
(defun health-chart-org-update ()
  "Refresh every health dynamic block in the buffer; return how many."
  (interactive)
  (let ((n (health-chart-org--update-blocks)))
    (when (called-interactively-p 'interactive)
      (message "health-chart: refreshed %d block%s" n (if (= n 1) "" "s")))
    n))

(defun health-chart-org-export-png (backend)
  "Before a LaTeX BACKEND export, re-run the chart blocks as PNG.
Runs in the export copy (`org-export-before-processing-functions'), so
the document keeps its SVG links; see `health-chart-org-latex-png'."
  (when (and health-chart-org-latex-png
             (fboundp 'org-export-derived-backend-p)
             (org-export-derived-backend-p backend 'latex))
    (let ((health-chart-org--export-format 'png))
      (health-chart-org--update-blocks '("health-chart")))))

(add-hook 'org-export-before-processing-functions #'health-chart-org-export-png)

(provide 'health-chart-org)
;;; health-chart-org.el ends here
