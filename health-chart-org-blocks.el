;;; health-chart-org-blocks.el --- Write the Org dynamic blocks -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; The writers behind the org-dblock-write: functions in health-chart-org.el.

;;; Code:

(require 'health-chart-org-base)
(require 'health-chart-org-explain)

;; -----------------------------------------------------------------------
;; Writing blocks
;; -----------------------------------------------------------------------

(defun health-chart-org--error-line (block err)
  "The Org comment line BLOCK writes for ERR."
  (let ((code (and (listp (cdr err)) (plist-get (cddr err) :code))))
    (format "# %s%s: %s" block (if code (format " (%s)" code) "")
            (health-chart-org--message err))))

(defun health-chart-org--prefer-utf-8 ()
  "Make the buffer's undecided file coding UTF-8, keeping its line ends.
Blocks insert glyphs such as ● that a locale code page cannot encode;
an ASCII file visited as `undecided' would otherwise make Emacs (and
org-persist, on killing the buffer) ask for a coding system."
  (when (and buffer-file-name
             (eq (coding-system-base buffer-file-coding-system) 'undecided))
    (set-buffer-file-coding-system
     (coding-system-change-text-conversion buffer-file-coding-system 'utf-8) nil t)))

(defmacro health-chart-org--guard (block &rest body)
  "Insert BODY's string; on any error insert BLOCK's error comment instead."
  (declare (indent 1) (debug t))
  `(progn
     (health-chart-org--prefer-utf-8)
     (insert (condition-case err
                 (progn ,@body)
               (error (health-chart-org--error-line ,block err))))))

(defun health-chart-org--chart (params)
  "The text a `health-chart' block with PARAMS writes, rendering the chart."
  (health-chart-org--check params)
  (let* ((kind (health-chart-org--chart-kind params))
         (data (health-chart-org--run-query (health-chart-org--chart-query params)))
         (props (health-chart-org--render-props params kind data))
         (caption (health-chart-org--str (plist-get params :caption))))
    (unless data
      (signal 'health-chart-org-error
              (list (format "no data for this %s chart; check :person, :marker, :category, :cohort and the dates"
                            kind)
                    :code "empty_chart")))
    (concat
     (when caption (format "#+CAPTION: %s\n" caption))
     (if (health-chart-org--text-chart-p params kind)
         (format "#+begin_example\n%s\n#+end_example"
                 (string-trim-right
                  (substring-no-properties (or (apply #'health-chart-plot kind data props) ""))))
       (let ((out (health-chart-org--output params kind)))
         (make-directory (file-name-directory out) t)
         (apply #'health-chart-write kind data out props)
         (format "#+ATTR_HTML: :alt %s\n[[file:%s]]"
                 (or caption (plist-get props :title) (format "%s chart" kind))
                 (health-chart-org--link-target out)))))))

(defun health-chart-org--cell (v)
  "V as an Org table cell: no bars or line breaks."
  (replace-regexp-in-string "[|\n\r]" " " (health-chart-org--str (or v "")) t t))

(defun health-chart-org--table-text (columns rows)
  "An aligned Org table of COLUMNS over ROWS (lists of cells)."
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "| " (mapconcat #'health-chart-org--cell columns " | ") " |\n|-\n")
    (dolist (row rows)
      (insert "| " (mapconcat #'health-chart-org--cell row " | ") " |\n"))
    (goto-char (point-min))
    (org-table-align)
    (string-trim-right (buffer-string))))

(defun health-chart-org--status-word (status)
  "Glyph and word for STATUS, e.g. \"▲ high\"."
  (health-chart-status-label status))

(defun health-chart-org--latest (params status)
  "Latest measurements for PARAMS, kept to STATUS values when non-nil."
  (let* ((query (health-chart-org--source-query
                 'latest (health-chart-org--fetch-args params)
                 (health-chart-org--measurement-filter params)))
         (ms (health-chart-fill-ranges (health-chart-org--run-query query)))
         (latest (apply #'append (mapcar (lambda (p) (health-chart-latest (health-chart-filter ms :person p)))
                                         (or (health-chart-persons ms) '(nil))))))
    (if status
        (seq-filter (lambda (m) (memq (health-chart-status m) status)) latest)
      latest)))

(defun health-chart-org--table (params)
  "The text a `health-table' block with PARAMS writes."
  (health-chart-org--check params)
  (let* ((ms (health-chart-org--latest params nil))
         (many (cdr (health-chart-persons ms))))
    (unless ms
      (signal 'health-chart-org-error
              (list "no measurements; check :person, :markers, :category and the dates"
                    :code "empty_table")))
    (concat
     (health-chart-org--plot-line params) "\n"
     (health-chart-org--table-text
      (if many (cons "Person" health-chart-org--table-columns) health-chart-org--table-columns)
      (mapcar (lambda (m)
                (append (when many (list (plist-get m :person)))
                        (list (health-chart-marker-label-in (plist-get m :marker) ms)
                              (health-chart-fmt (plist-get m :value))
                              (plist-get m :unit) (plist-get m :date)
                              (health-chart-org--status-word (health-chart-status m))
                              (health-chart-fmt-range (plist-get m :ref-low) (plist-get m :ref-high))
                              (health-chart-fmt-range (plist-get m :opt-low) (plist-get m :opt-high)))))
              ms)))))

(defun health-chart-org--scorecard (params)
  "The text a `health-scorecard' block with PARAMS writes."
  (let ((plan (health-chart-org-scorecard-explain params)))
    (unless (eq (plist-get plan :valid) t)
      (signal 'health-chart-org-error
              (list (plist-get plan :valid) :code (or (plist-get plan :code) "invalid_block"))))
    (let ((rows (health-chart-model-scorecard
                 (health-chart-org--run-query (plist-get plan :query)))))
      (health-chart-org--table-text
       health-chart-org--scorecard-columns
       (mapcar (lambda (r)
                 (list (plist-get r :label) (health-chart-fmt (plist-get r :value))
                       (plist-get r :unit) (plist-get r :date)
                       (health-chart-org--status-word (plist-get r :status))
                       (let ((label (health-chart-indicator-trend-label (plist-get r :trend)
                                                                        (plist-get r :series))))
                         (if (string-empty-p label) "–" label))))
               rows)))))

(defun health-chart-org--flags (params)
  "The text a `health-flags' block with PARAMS writes."
  (health-chart-org--check params)
  (let ((ms (health-chart-org--latest params '(low high))))
    (if (null ms)
        (format "- %s No markers out of range." (health-chart-status-label 'optimal))
      (mapconcat
       (lambda (m)
         (format "- %s · *%s* %s %s (%s)%s%s"
                 (health-chart-org--status-word (health-chart-status m))
                 (health-chart-marker-label-in (plist-get m :marker) ms)
                 (health-chart-fmt (plist-get m :value)) (or (plist-get m :unit) "")
                 (plist-get m :date)
                 (let ((r (health-chart-fmt-range (plist-get m :ref-low) (plist-get m :ref-high))))
                   (if (string-empty-p r) "" (format ", reference %s" r)))
                 (if (and (cdr (health-chart-persons ms)) (plist-get m :person))
                     (format " — %s" (plist-get m :person)) "")))
       ms "\n"))))

(provide 'health-chart-org-blocks)
;;; health-chart-org-blocks.el ends here
