;;; health-chart-org-explain.el --- Pure plans of what each Org block would do -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; The explain twins of the dynamic blocks: what a block would fetch
;; and write, without running anything.

;;; Code:

(require 'health-chart-org-base)

;; -----------------------------------------------------------------------
;; Explain twins (pure)
;; -----------------------------------------------------------------------

(defun health-chart-org--clean (params)
  "PARAMS without the keys Org itself puts in a block's params."
  (apply #'health-chart--plist-drop params health-chart-org--internal-params))

(defun health-chart-org--guard-explain (block params fn)
  "FN's plan for BLOCK with PARAMS, or (:block :valid MESSAGE) when invalid."
  (condition-case err
      (append (list :block block :params (health-chart-org--clean params) :valid t)
              (funcall fn))
    (health-chart-error (list :block block :params (health-chart-org--clean params)
                              :valid (health-chart-org--message err)
                              :code (and (listp (cdr err)) (plist-get (cddr err) :code))))))

(defun health-chart-org-chart-explain (params &optional org-file)
  "The plan of a `health-chart' block with PARAMS in ORG-FILE.  Pure.
A plist: :block :params :valid (t or the error message, then with
its :code) :kind :query
\(what is fetched: source :function :command :args :filter, or the
cohort :plans) :output (the file written, nil for a text chart) :link
:format :mode (image or text) :render (the props given to
`health-chart-write')."
  (health-chart-org--guard-explain
   "health-chart" params
   (lambda ()
     (health-chart-org--check params)
     (let* ((kind (health-chart-org--chart-kind params))
            (text (health-chart-org--text-chart-p params kind))
            (out (unless text (health-chart-org--output params kind org-file))))
       (list :kind kind :query (health-chart-org--chart-query params)
             :mode (if text 'text 'image)
             :format (if text 'text (health-chart-org--format params))
             :output out
             :link (when out (health-chart-org--link-target out org-file))
             :render (health-chart-org--render-props params kind nil))))))

(defun health-chart-org-table-explain (params &optional _org-file)
  "The plan of a `health-table' block with PARAMS.  Pure.
A plist: :block :params :valid :query (the source `latest' call and the
local filter) :columns :plot (the #+PLOT line)."
  (health-chart-org--guard-explain
   "health-table" params
   (lambda ()
     (health-chart-org--check params)
     (list :query (health-chart-org--source-query
                   'latest (health-chart-org--fetch-args params)
                   (health-chart-org--measurement-filter params))
           :columns health-chart-org--table-columns
           :plot (health-chart-org--plot-line params)))))

(defun health-chart-org-scorecard-explain (params &optional _org-file)
  "The plan of a `health-scorecard' block with PARAMS.  Pure.
A plist: :block :params :valid :query (one cohort values plan per
cohort) :columns."
  (health-chart-org--guard-explain
   "health-scorecard" params
   (lambda ()
     (health-chart-org--check params)
     (unless (plist-get params :cohort)
       (signal 'health-chart-org-error
               (list (format "health-scorecard needs :cohort NAME (one of %s)"
                             (mapconcat #'symbol-name (health-chart-cohort-names) " "))
                     :code "missing_param" :param :cohort)))
     (mapc #'health-chart-resolve-cohort (health-chart-org--cohorts params))
     (list :query (health-chart-org--cohort-query params)
           :columns health-chart-org--scorecard-columns))))

(defun health-chart-org-flags-explain (params &optional _org-file)
  "The plan of a `health-flags' block with PARAMS.  Pure.
A plist: :block :params :valid :query (the source `latest' call and the
local filter; out-of-range values are kept)."
  (health-chart-org--guard-explain
   "health-flags" params
   (lambda ()
     (health-chart-org--check params)
     (list :query (health-chart-org--source-query
                   'latest (health-chart-org--fetch-args params)
                   (append (health-chart-org--measurement-filter params)
                           (list :status '(low high))))))))

(defun health-chart-org--genetics-section (params)
  "The genetics section PARAMS ask for, or signal."
  (let ((section (or (health-chart-org--sym (plist-get params :section)) 'summary)))
    (unless (memq section health-chart-org-genetics-sections)
      (signal 'health-chart-org-error
              (list (format ":section must be one of %s, got %s"
                            (mapconcat #'symbol-name health-chart-org-genetics-sections " ")
                            section)
                    :code "invalid_param" :param :section)))
    section))

(defun health-chart-org-genetics-explain (params &optional _org-file)
  "The plan of a `health-genetics' block with PARAMS.  Pure.
A plist: :block :params :valid :section :delegate (the genetics.el
block writer called) :available (whether it is defined) :args (what
it gets)."
  (health-chart-org--guard-explain
   "health-genetics" params
   (lambda ()
     (let* ((section (health-chart-org--genetics-section params))
            (fn (intern (format "org-dblock-write:genetics-%s" section))))
       (list :section section :delegate fn :available (fboundp fn)
             :args (health-chart--plist-drop (health-chart-org--clean params) :section))))))

(defun health-chart-org-explain (block params &optional org-file)
  "The plan of dynamic BLOCK (a name in `health-chart-org-blocks') with PARAMS.
ORG-FILE is the document (default: the current buffer's).  Pure."
  (let ((entry (assoc (health-chart-org--str block) health-chart-org-blocks)))
    (unless entry
      (signal 'health-chart-org-error
              (list (format "unknown block %s; use one of %s" block
                            (mapconcat #'car health-chart-org-blocks " "))
                    :code "unknown_block")))
    (funcall (nth 1 entry) params org-file)))

(defun health-chart-org-explain-block ()
  "The plan of the health block at point (see `health-chart-org-explain').
Interactively, show it in the echo area."
  (interactive)
  (save-excursion
    (end-of-line)
    (unless (re-search-backward "^[ \t]*#\\+BEGIN:[ \t]+\\(health-[a-z-]+\\)\\(.*\\)$" nil t)
      (user-error "Not in a health dynamic block"))
    (let ((plan (health-chart-org-explain (match-string-no-properties 1)
                                          (car (read-from-string
                                                (concat "(" (match-string-no-properties 2) ")"))))))
      (when (called-interactively-p 'interactive) (message "%S" plan))
      plan)))

(provide 'health-chart-org-explain)
;;; health-chart-org-explain.el ends here
