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

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'org)
(require 'health-chart-core)
(require 'health-chart-source)
(require 'health-chart-template)
(require 'health-chart-render)
(require 'health-chart-plot)
(require 'health-chart-cohort)
(require 'health-chart-genetics)

(declare-function org-export-derived-backend-p "ox" (backend &rest backends))

(define-error 'health-chart-org-error
  "health-chart: Org report error" 'health-chart-error)

(defcustom health-chart-org-asset-directory "%s-assets"
  "Where an Org document's chart images go.
A directory name, relative to the document's directory unless absolute;
%s stands for the document's file name without extension (\"report\"
for an unsaved buffer)."
  :type 'string
  :group 'health-charts)

(defcustom health-chart-org-image-format 'svg
  "Image format of `health-chart' blocks without a :format param."
  :type '(choice (const svg) (const png) (const pdf))
  :group 'health-charts)

(defcustom health-chart-org-theme 'light
  "Chart theme in Org reports; light suits exported pages."
  :type '(choice (const light) (const dark) (const auto))
  :group 'health-charts)

(defcustom health-chart-org-latex-png t
  "Non-nil: LaTeX/PDF export re-runs `health-chart' blocks as PNG.
Only the export copy changes; the document keeps its SVG links.  A block
with an explicit :format keeps it."
  :type 'boolean
  :group 'health-charts)

(defcustom health-chart-org-template-directories nil
  "Directories searched for Org report templates before the bundled ones.
Each holds NAME.org files; a user file shadows the bundled template of
the same name."
  :type '(repeat directory)
  :group 'health-charts)

(defconst health-chart-org-bundled-template-directory
  (expand-file-name "templates/org" (file-name-directory (or load-file-name buffer-file-name
                                                             default-directory)))
  "The report templates shipped with health-chart.")

(defconst health-chart-org-blocks
  '(("health-chart" health-chart-org-chart-explain
     "A chart image (or a text chart) written to the asset directory.")
    ("health-table" health-chart-org-table-explain
     "The latest value per marker as an Org table with a #+PLOT line.")
    ("health-scorecard" health-chart-org-scorecard-explain
     "A cohort's indicator values with status and trend.")
    ("health-flags" health-chart-org-flags-explain
     "Markers whose latest value is out of range, as a list.")
    ("health-genetics" health-chart-org-genetics-explain
     "genetics.el's summary, hits or APOE block, when genetics.el is loaded.")
    ("health-genetics-labs" health-chart-org-genetics-labs-explain
     "Each linked gene's call next to its lab markers' latest values and charts."))
  "The dynamic blocks: (NAME EXPLAIN-FUNCTION DOC).")

(defconst health-chart-org-genetics-sections '(summary hits apoe)
  "Sections `health-genetics' delegates to genetics.el.")

(defconst health-chart-org--table-columns
  '("Marker" "Value" "Unit" "Date" "Status" "Reference" "Optimal")
  "Columns of a `health-table'.")

(defconst health-chart-org--scorecard-columns
  '("Indicator" "Value" "Unit" "Date" "Status" "Trend")
  "Columns of a `health-scorecard'.")

(defvar health-chart-org--export-format nil
  "Image format forced while exporting (png for LaTeX), else nil.")

;; -----------------------------------------------------------------------
;; Params
;; -----------------------------------------------------------------------

(defconst health-chart-org--internal-params '(:name :indentation-column :content)
  "Keys Org adds to a dynamic block's params.")

(defun health-chart-org--str (v)
  "Param V as a string (symbols and numbers too), or nil."
  (cond ((null v) nil) ((stringp v) v) (t (format "%s" v))))

(defun health-chart-org--sym (v)
  "Param V as a symbol, or nil."
  (cond ((null v) nil) ((symbolp v) v) (t (intern (format "%s" v)))))

(defun health-chart-org--list (v)
  "Param V as a list of strings: a list, a symbol or a space-separated string."
  (cond ((null v) nil)
        ((listp v) (mapcar #'health-chart-org--str v))
        ((stringp v) (split-string v "[ ,]+" t))
        (t (list (health-chart-org--str v)))))

(defun health-chart-org--person (params)
  "The person PARAMS select: :person, else `health-chart-default-person'."
  (if (plist-member params :person)
      (health-chart-org--str (plist-get params :person))
    health-chart-default-person))

(defun health-chart-org--markers (params)
  "The markers PARAMS select (:marker and :markers), or nil for all."
  (append (health-chart-org--list (plist-get params :marker))
          (health-chart-org--list (plist-get params :markers))))

(defun health-chart-org--cohorts (params)
  "The cohorts PARAMS' :cohort names, as symbols."
  (mapcar #'intern (health-chart-org--list (plist-get params :cohort))))

(defun health-chart-org--check-date (params key)
  "Signal unless PARAMS' KEY is absent or a YYYY-MM-DD date."
  (let ((d (plist-get params key)))
    (when (and d (not (health-chart-date-p (health-chart-org--str d))))
      (signal 'health-chart-org-error
              (list (format "%s must be a date like \"2025-01-31\", got %S" key d)
                    :code "invalid_param" :param key)))))

(defun health-chart-org--check (params)
  "Signal when PARAMS' dates are malformed."
  (dolist (key '(:since :until :as-of :baseline))
    (health-chart-org--check-date params key)))

;; -----------------------------------------------------------------------
;; Queries (pure plans of what a block fetches)
;; -----------------------------------------------------------------------

(defun health-chart-org--fetch-args (params &optional keys)
  "The source arguments PARAMS give, for KEYS (default person, since, until)."
  (let ((markers (health-chart-org--markers params)))
    (cl-loop for key in (or keys '(:person :marker :since :until))
             for v = (pcase key
                       (:person (health-chart-org--person params))
                       (:marker (and (= (length markers) 1) (car markers)))
                       (_ (health-chart-org--str (plist-get params key))))
             when (or v (eq key :person)) append (list key v))))

(defun health-chart-org--source-query (command args filter)
  "A measurement query plan: source COMMAND with ARGS, then FILTER locally."
  (append (list :function health-chart-source-function :command command :args args
                :filter filter)
          (when (eq health-chart-source-function #'health-chart-source-cli)
            (list :argv (cons health-chart-source-executable
                              (apply #'health-chart-source-cli-args command args))))))

(defun health-chart-org--measurement-filter (params)
  "The local filter of PARAMS: (:marker MARKERS :category CATEGORY)."
  (list :marker (health-chart-org--markers params)
        :category (health-chart-org--str (plist-get params :category))))

(defun health-chart-org--cohort-query (params)
  "A cohort query plan for PARAMS: one `health-chart-cohort-values' per cohort."
  (let ((args (append (health-chart-org--fetch-args params '(:person :since :until))
                      (when (plist-get params :as-of)
                        (list :as-of (health-chart-org--str (plist-get params :as-of)))))))
    (list :function #'health-chart-cohort-values
          :cohorts (health-chart-org--cohorts params) :args args
          :plans (mapcar (lambda (c) (apply #'health-chart-cohort-values-explain c args))
                         (health-chart-org--cohorts params)))))

(defun health-chart-org--chart-kind (params)
  "The chart kind PARAMS ask for, defaulting by what they select."
  (or (health-chart-org--sym (plist-get params :kind))
      (cond ((plist-get params :cohort) 'staleness)
            ((= (length (health-chart-org--markers params)) 1) 'timeseries)
            (t 'panel))))

(defun health-chart-org--chart-query (params)
  "The data query plan of a `health-chart' block with PARAMS."
  (let* ((kind (health-chart-org--chart-kind params))
         (shape (plist-get (health-chart--kind kind) :shape)))
    (if (eq shape 'indicators)
        (progn
          (unless (plist-get params :cohort)
            (signal 'health-chart-org-error
                    (list (format "kind %s charts indicator values; add :cohort NAME (one of %s)"
                                  kind (mapconcat #'symbol-name (health-chart-cohort-names) " "))
                          :code "missing_param" :param :cohort)))
          (health-chart-org--cohort-query params))
      (let* ((args (health-chart-org--fetch-args params))
             ;; compare overlays people: no :person means everyone
             (args (if (and (eq kind 'compare) (not (plist-member params :person)))
                       (plist-put args :person nil)
                     args))
             ;; delta against a baseline needs the draws before :since
             (args (if (plist-get params :baseline) (health-chart--plist-drop args :since) args)))
        (health-chart-org--source-query
         (if (plist-get args :marker) 'trend 'query) args
         (health-chart-org--measurement-filter params))))))

(defun health-chart-org--run-query (query)
  "Fetch QUERY's data: measurements or indicator values."
  (if (plist-get query :cohorts)
      (apply #'append (mapcar (lambda (c) (apply #'health-chart-cohort-values c
                                                 (plist-get query :args)))
                              (plist-get query :cohorts)))
    (let ((filter (plist-get query :filter)))
      (health-chart-filter (apply #'health-chart-source-fetch (plist-get query :command)
                                  (plist-get query :args))
                           :marker (plist-get filter :marker)
                           :category (plist-get filter :category)))))

;; -----------------------------------------------------------------------
;; Files
;; -----------------------------------------------------------------------

(defun health-chart-org--document (&optional org-file)
  "The document file ORG-FILE, else the current buffer's file, or nil."
  (or org-file (buffer-file-name (buffer-base-buffer))))

(defun health-chart-org--document-dir (&optional org-file)
  "Directory of the document ORG-FILE (default: the current one)."
  (let ((doc (health-chart-org--document org-file)))
    (if doc (file-name-directory (expand-file-name doc)) default-directory)))

(defun health-chart-org-asset-dir (&optional org-file)
  "The asset directory of document ORG-FILE (default: the current buffer's)."
  (let ((doc (health-chart-org--document org-file)))
    (file-name-as-directory
     (expand-file-name (format health-chart-org-asset-directory
                               (if doc (file-name-base doc) "report"))
                       (health-chart-org--document-dir org-file)))))

(defun health-chart-org--slug (s)
  "S as a lower-case file-name slug."
  (string-trim (replace-regexp-in-string "[^a-z0-9]+" "-" (downcase s)) "-" "-"))

(defconst health-chart-org--name-params
  '(:kind :person :marker :markers :category :cohort :since :until :as-of :baseline
          :backend :width :height :title :columns)
  "The params a chart's file name derives from.")

(defun health-chart-org--file-name (params kind format)
  "Stable file name for a KIND chart in FORMAT from PARAMS.
Readable words (kind, person, markers, category, cohort) plus a short
hash of every param that changes the picture; same params, same name."
  (let* ((words (delq nil (append (list (symbol-name kind)
                                        (health-chart-org--person params))
                                  (health-chart-org--markers params)
                                  (list (health-chart-org--str (plist-get params :category)))
                                  (health-chart-org--list (plist-get params :cohort)))))
         (key (prin1-to-string (cl-loop for k in health-chart-org--name-params
                                        when (plist-member params k)
                                        collect (cons k (plist-get params k)))))
         (stem (truncate-string-to-width (health-chart-org--slug (string-join words "-")) 60)))
    (format "%s-%s.%s" (string-trim-right stem "-") (substring (md5 key) 0 8) format)))

(defun health-chart-org--format (params)
  "The image format of a chart block with PARAMS."
  (or (health-chart-org--sym (plist-get params :format))
      health-chart-org--export-format
      health-chart-org-image-format))

(defun health-chart-org--text-chart-p (params kind)
  "Non-nil when KIND under PARAMS renders as text rather than an image."
  (or (eq (health-chart-org--sym (plist-get params :backend)) 'text)
      (not (health-chart--template-kind-p kind))))

(defun health-chart-org--output (params kind &optional org-file)
  "The output file of a KIND chart block with PARAMS in document ORG-FILE."
  (let ((file (plist-get params :file)))
    (if file
        (expand-file-name (health-chart-org--str file) (health-chart-org--document-dir org-file))
      (expand-file-name (health-chart-org--file-name params kind (health-chart-org--format params))
                        (health-chart-org-asset-dir org-file)))))

(defun health-chart-org--link-target (file &optional org-file)
  "FILE relative to the document ORG-FILE's directory, for a link."
  (file-relative-name file (health-chart-org--document-dir org-file)))

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

(defconst health-chart-org--genetics-labs-chart-size '(360 . 180)
  "Pixel (WIDTH . HEIGHT) of a `health-genetics-labs' marker chart.")

(defun health-chart-org--genetics-labs-charts-p (params)
  "Non-nil unless PARAMS turn the per-marker charts off (:charts nil)."
  (let ((v (plist-get params :charts)))
    (not (and (plist-member params :charts) (memq v '(nil no none off))))))

(defun health-chart-org--genetics-labs-chart-params (params marker)
  "The `health-chart' params of PARAMS' small time series of MARKER."
  (append (list :kind 'timeseries)
          (when (plist-member params :person)
            (list :person (health-chart-org--person params)))
          (list :marker marker)
          (cl-loop for key in '(:since :until :backend :format)
                   when (plist-get params key) append (list key (plist-get params key)))
          (list :width (or (plist-get params :width) (car health-chart-org--genetics-labs-chart-size))
                :height (or (plist-get params :height) (cdr health-chart-org--genetics-labs-chart-size))
                :caption (health-chart-marker-label marker))))

(defun health-chart-org--genetics-labs-query (params links)
  "The source `latest' plan for LINKS' markers under PARAMS, or nil if none."
  (let ((spellings (seq-mapcat (lambda (l) (seq-mapcat #'health-chart-genetics-marker-spellings
                                                       (plist-get l :markers)))
                               links)))
    (when spellings
      (let ((params (append (list :markers spellings)
                            (health-chart--plist-drop params :marker :markers))))
        (health-chart-org--source-query 'latest (health-chart-org--fetch-args params)
                                        (health-chart-org--measurement-filter params))))))

(defun health-chart-org-genetics-labs-explain (params &optional org-file)
  "The plan of a `health-genetics-labs' block with PARAMS in ORG-FILE.  Pure.
A plist: :block :params :valid :genetics (the genetics.el calls, from
`health-chart-genetics-calls-explain') :query (the source `latest'
call for every linked marker, nil when none) :genes (each :gene :rsids
:markers :note :rationale :source and :charts, ((MARKER . PLAN)...)
with each marker chart's `health-chart-org-chart-explain' plan)
:disclaimer.  Calls neither genetics.el nor the source."
  (health-chart-org--guard-explain
   "health-genetics-labs" params
   (lambda ()
     (health-chart-org--check params)
     (let* ((genes (health-chart-org--list (plist-get params :genes)))
            (links (health-chart-genetics-links genes))
            (charts (health-chart-org--genetics-labs-charts-p params)))
       (list :genetics (health-chart-genetics-calls-explain
                        (health-chart-org--str (plist-get params :kit))
                        (health-chart-org--str (plist-get params :file))
                        genes)
             :query (health-chart-org--genetics-labs-query params links)
             :genes (mapcar
                     (lambda (l)
                       (let ((markers (mapcar #'health-chart-genetics-marker-id (plist-get l :markers))))
                         (list :gene (plist-get l :gene) :rsids (plist-get l :rsids)
                               :markers markers :note (plist-get l :note)
                               :rationale (plist-get l :rationale) :source (plist-get l :source)
                               :charts (when charts
                                         (mapcar (lambda (m)
                                                   (cons m (health-chart-org-chart-explain
                                                            (health-chart-org--genetics-labs-chart-params
                                                             params m)
                                                            org-file)))
                                                 markers)))))
                     links)
             :disclaimer health-chart-genetics-disclaimer)))))

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

;; -----------------------------------------------------------------------
;; Writing blocks
;; -----------------------------------------------------------------------

(defun health-chart-org--message (err)
  "The runbook message of ERR, on one line."
  (replace-regexp-in-string
   "[\n\r]+" " "
   (if (stringp (cadr err)) (cadr err) (error-message-string err))))

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

(defun health-chart-org--render-props (params kind data)
  "Props for `health-chart-write' drawing KIND of DATA under block PARAMS."
  (let* ((shape (plist-get (health-chart--kind kind) :shape))
         (marker (car (health-chart-org--markers params)))
         (marker (if (and data marker (eq shape 'measurements))
                     (or (seq-find (lambda (m) (health-chart-marker-equal m marker))
                                   (health-chart-markers data))
                         marker)
                   marker))
         (person (health-chart-org--person params)))
    (append
     (when (and person (eq shape 'measurements)) (list :person person))
     (when (and marker (memq kind '(timeseries compare))) (list :marker marker))
     (when (plist-get params :as-of)
       (list :as-of (health-chart-org--str (plist-get params :as-of))))
     (cl-loop for (param prop) in '((:title :title) (:columns :columns) (:from :from) (:to :to)
                                    (:due-days :due-days) (:stale-days :stale-days))
              when (plist-get params param)
              append (list prop (let ((v (plist-get params param)))
                                  (if (symbolp v) (symbol-name v) v))))
     (when (and (eq kind 'delta) data (plist-get params :baseline))
       (health-chart-org--baseline-props params data person))
     (if (health-chart-org--text-chart-p params kind)
         (list :backend 'text)
       (append
        (when (plist-get params :backend) (list :backend (health-chart-org--sym (plist-get params :backend))))
        (when (plist-get params :width) (list :pixel-width (plist-get params :width)))
        (when (plist-get params :height) (list :pixel-height (plist-get params :height)))
        ;; print wants more pixels than the screen
        (when (eq (health-chart-org--format params) 'png) (list :scale 2))
        (list :theme health-chart-org-theme))))))

(defun health-chart-org--baseline-props (params data person)
  "(:from :to) comparing the draw at PARAMS' :baseline with the latest in DATA.
:from is PERSON's last draw on or before the baseline date."
  (let* ((dates (health-chart-dates (if person (health-chart-filter data :person person) data)))
         (baseline (health-chart-org--str (plist-get params :baseline)))
         (from (car (last (seq-remove (lambda (d) (string< baseline d)) dates))))
         (to (car (last dates))))
    (unless (and from (not (equal from to)))
      (signal 'health-chart-org-error
              (list (format "no draw on or before :baseline %s to compare with %s; draws: %s"
                            baseline to (string-join dates ", "))
                    :code "no_baseline")))
    (list :from from :to to)))

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

(defun health-chart-org--plot-line (params)
  "The #+PLOT line of a `health-table' with PARAMS."
  (format "#+PLOT: title:\"Latest values%s\" ind:1 deps:(2) type:2d with:histograms set:\"style fill solid 0.6\" set:\"xtics rotate by -45\""
          (let ((p (health-chart-org--person params))) (if p (format " · %s" p) ""))))

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

(defun health-chart-org--value-line (m ms)
  "One list item for measurement M (labelled from MS): status, value, date, range."
  (format "- %s · *%s* %s %s (%s)%s"
          (health-chart-org--status-word (health-chart-status m))
          (health-chart-marker-label-in (plist-get m :marker) ms)
          (health-chart-fmt (plist-get m :value)) (or (plist-get m :unit) "")
          (plist-get m :date)
          (let ((r (health-chart-fmt-range (plist-get m :ref-low) (plist-get m :ref-high))))
            (if (string-empty-p r) "" (format ", reference %s" r)))))

(defun health-chart-org--genetics-labs-calls (plan)
  "Fetch the genotypes of the genetics PLAN as (SUMMARIES . NOTE).
SUMMARIES are per gene; NOTE says why there are none, else nil."
  (let ((g (plist-get plan :genetics)))
    (if (not (plist-get g :available))
        (cons nil (format "/Genotypes not shown: genetics.el is not loaded (%s and %s are undefined); load it, or set =health-chart-genetics-functions=, and refresh this block./"
                          (nth 0 (plist-get g :kit)) (plist-get g :genotype)))
      (condition-case err
          (cons (health-chart-genetics-calls (nth 1 (plist-get g :kit)) (nth 2 (plist-get g :kit))
                                             (mapcar (lambda (x) (plist-get x :gene))
                                                     (plist-get g :genes)))
                nil)
        (error (cons nil (format "/Genotypes not shown: %s/" (health-chart-org--message err))))))))

(defun health-chart-org--genetics-labs-gene (gene summary note ms params)
  "The paragraph of GENE's explain plan with its call SUMMARY.
NOTE is non-nil when no genotypes are available; MS are the latest
measurements; PARAMS the block's."
  (let* ((rsids (string-join (plist-get gene :rsids) ", "))
         (call (cond (note (format "*%s* (%s)." (plist-get gene :gene) rsids))
                     ((not (plist-get summary :called))
                      (format "*%s*: no call at %s in this kit." (plist-get gene :gene) rsids))
                     (t (format "*%s* · %s." (plist-get gene :gene)
                                (health-chart-genetics-call-text summary)))))
         (source (plist-get gene :source))
         (why (format "%s%s%s" (plist-get gene :rationale)
                      (if (plist-get gene :note) (format " %s" (plist-get gene :note)) "")
                      (if source (format " [[%s][%s]]" (cdr source) (car source)) ""))))
    (if (null (plist-get gene :markers))
        (format "%s %s" call why)
      (let ((found (mapcar (lambda (m)
                             (cons m (seq-find (lambda (x) (seq-some (lambda (s) (health-chart-marker-equal
                                                                                  s (plist-get x :marker)))
                                                                     (health-chart-genetics-marker-spellings m)))
                                               ms)))
                           (plist-get (health-chart-genetics-link (plist-get gene :gene)) :markers))))
        (string-join
         (delq nil
               (list
                (format "%s %s" call why)
                (mapconcat (lambda (f)
                             (if (cdr f) (health-chart-org--value-line (cdr f) ms)
                               (format "- *%s*: no results on file."
                                       (health-chart-marker-label
                                        (health-chart-genetics-marker-id (car f))))))
                           found "\n")
                (when (health-chart-org--genetics-labs-charts-p params)
                  (let ((charts
                         (delq nil
                               (mapcar (lambda (f)
                                         (when (cdr f)
                                           (condition-case err
                                               (health-chart-org--chart
                                                (health-chart-org--genetics-labs-chart-params
                                                 params (plist-get (cdr f) :marker)))
                                             (error (health-chart-org--error-line "health-genetics-labs" err)))))
                                       found))))
                    (when charts (string-join charts "\n\n"))))))
         "\n\n")))))

(defun health-chart-org--genetics-labs (params)
  "The text a `health-genetics-labs' block with PARAMS writes."
  (let ((plan (health-chart-org-genetics-labs-explain params)))
    (unless (eq (plist-get plan :valid) t)
      (signal 'health-chart-org-error
              (list (plist-get plan :valid) :code (or (plist-get plan :code) "invalid_block"))))
    (let* ((calls (health-chart-org--genetics-labs-calls plan))
           (note (cdr calls))
           (query (plist-get plan :query))
           (ms (when query
                 (let ((all (health-chart-fill-ranges (health-chart-org--run-query query))))
                   (apply #'append (mapcar (lambda (p) (health-chart-latest (health-chart-filter all :person p)))
                                           (or (health-chart-persons all) '(nil))))))))
      (string-join
       (append (when note (list note))
               (mapcar (lambda (gene)
                         (health-chart-org--genetics-labs-gene
                          gene (seq-find (lambda (s) (equal (plist-get s :gene) (plist-get gene :gene)))
                                         (car calls))
                          note ms params))
                       (plist-get plan :genes))
               (list (format "/%s/" health-chart-genetics-disclaimer)))
       "\n\n"))))

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

;; -----------------------------------------------------------------------
;; Report templates
;; -----------------------------------------------------------------------

(defun health-chart-org-template-directories ()
  "Report template directories in search order: the user's, then the bundled."
  (append (mapcar #'expand-file-name health-chart-org-template-directories)
          (list health-chart-org-bundled-template-directory)))

(defun health-chart-org--template-title (file)
  "The #+TITLE of template FILE, placeholders and all, or nil."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file nil 0 2000))
    (when (re-search-forward "^#\\+TITLE:[ \t]*\\(.*\\)$" nil t)
      (string-trim (match-string 1)))))

(defun health-chart-org-template-list ()
  "Every report template as (:name :path :source :title), first match wins.
:source is user or bundled."
  (let (found)
    (dolist (dir (health-chart-org-template-directories))
      (when (file-directory-p dir)
        (dolist (file (directory-files dir t "\\.org\\'"))
          (let ((name (file-name-base file)))
            (unless (assoc name found)
              (push (cons name (list :name name :path file
                                     :source (if (equal dir health-chart-org-bundled-template-directory)
                                                 'bundled 'user)
                                     :title (health-chart-org--template-title file)))
                    found))))))
    (mapcar #'cdr (sort found (lambda (a b) (string< (car a) (car b)))))))

;;;###autoload
(defun health-chart-org-templates ()
  "List the report templates; interactively, show them in a buffer."
  (interactive)
  (let ((templates (health-chart-org-template-list)))
    (when (called-interactively-p 'interactive)
      (with-current-buffer (get-buffer-create "*health-chart org templates*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (dolist (tpl templates)
            (insert (format "%-22s %-8s %s\n  %s\n" (plist-get tpl :name) (plist-get tpl :source)
                            (or (plist-get tpl :title) "")
                            (abbreviate-file-name (plist-get tpl :path))))))
        (special-mode)
        (pop-to-buffer (current-buffer))))
    templates))

(defun health-chart-org-template-find (name)
  "The file of report template NAME, or signal."
  (or (plist-get (seq-find (lambda (tpl) (equal (plist-get tpl :name) name))
                           (health-chart-org-template-list))
                 :path)
      (signal 'health-chart-org-error
              (list (format "no report template %S; use one of %s (or add NAME.org to `health-chart-org-template-directories')"
                            name (mapconcat (lambda (tpl) (plist-get tpl :name))
                                            (health-chart-org-template-list) " "))
                    :code "unknown_template" :template name))))

(defun health-chart-org--year-before (date)
  "DATE one year earlier (Feb 29 becomes Feb 28)."
  (let ((y (string-to-number (substring date 0 4))) (md (substring date 4)))
    (format "%04d%s" (1- y) (if (equal md "-02-29") "-02-28" md))))

(defun health-chart-org-context (&rest args)
  "The placeholder context of a report from ARGS.
ARGS: :person (default `health-chart-default-person'), :date (default
today), :until (default :date), :since (default a year before
:until).  Adds :period (\"SINCE – UNTIL\") and :year (of :until)."
  (let* ((date (or (plist-get args :date) (format-time-string "%Y-%m-%d")))
         (until (or (plist-get args :until) date))
         (since (or (plist-get args :since) (health-chart-org--year-before until))))
    (dolist (d (list date since until))
      (unless (health-chart-date-p d)
        (signal 'health-chart-org-error
                (list (format "report dates must look like 2025-01-31, got %S" d)
                      :code "invalid_param"))))
    (list :person (or (plist-get args :person) health-chart-default-person "")
          :date date :since since :until until
          :period (format "%s – %s" since until)
          :year (substring until 0 4))))

(defun health-chart-org--template-file (template)
  "TEMPLATE's file: itself when absolute, else found by name."
  (if (file-name-absolute-p template) template (health-chart-org-template-find template)))

(defun health-chart-org-stamp (template context)
  "Report TEMPLATE (a name or file) filled from CONTEXT; return the text.
Pure apart from reading the template.  CONTEXT is a plist from
`health-chart-org-context'; an unknown placeholder signals, naming the
template file and line."
  (let ((file (health-chart-org--template-file template)))
    (health-chart-template-fill (health-chart-template-read file) context 'text file)))

(defun health-chart-org-new-report-explain (template output &rest args)
  "The plan of `health-chart-org-new-report' for TEMPLATE, OUTPUT, ARGS.  Pure.
A plist: :template (its file) :output :context :assets :blocks (each
block's explain plan, in document order)."
  (let* ((context (apply #'health-chart-org-context args))
         (output (expand-file-name output))
         (text (health-chart-org-stamp template context))
         (blocks nil) (start 0))
    (while (string-match "^[ \t]*#\\+BEGIN:[ \t]+\\(health-[a-z-]+\\)\\(.*\\)$" text start)
      (let ((name (match-string 1 text)) (raw (match-string 2 text)))
        (setq start (match-end 0))
        (when (assoc name health-chart-org-blocks)
          (push (health-chart-org-explain name (car (read-from-string (concat "(" raw ")"))) output)
                blocks))))
    (list :template (health-chart-org--template-file template) :output output :context context
          :assets (health-chart-org-asset-dir output) :blocks (nreverse blocks))))

;;;###autoload
(defun health-chart-org-new-report (template output &rest args)
  "Stamp report TEMPLATE into OUTPUT, refresh its blocks, open it; return OUTPUT.
ARGS: :person :date :since :until (see `health-chart-org-context').
Interactively, prompts for each and confirms before overwriting an
existing OUTPUT.  See `health-chart-org-new-report-explain'."
  (interactive
   (let* ((tpl (completing-read "Report template: "
                                (mapcar (lambda (tpl) (plist-get tpl :name))
                                        (health-chart-org-template-list))
                                nil t))
          (person (read-string "Person: " health-chart-default-person))
          (until (read-string "Period ends: " (format-time-string "%Y-%m-%d")))
          (since (read-string "Period starts: " (health-chart-org--year-before until)))
          (out (read-file-name "Write report to: " nil nil nil
                               (format "%s-%s-%s.org" tpl (health-chart-org--slug person) until))))
     (when (and (file-exists-p out)
                (not (y-or-n-p (format "%s exists; overwrite? " out))))
       (user-error "Not overwriting %s" out))
     (list tpl out :person person :since since :until until)))
  (let* ((output (expand-file-name output))
         (text (health-chart-org-stamp template (apply #'health-chart-org-context args))))
    (make-directory (file-name-directory output) t)
    (let ((coding-system-for-write 'utf-8-unix))
      (write-region text nil output nil 'silent))
    (with-current-buffer (find-file-noselect output)
      (let ((coding-system-for-read 'utf-8-unix))
        (revert-buffer t t t))
      ;; blocks insert non-ASCII glyphs; never prompt for a coding on save
      (set-buffer-file-coding-system 'utf-8-unix)
      (health-chart-org-update)
      (save-buffer)
      (unless noninteractive (pop-to-buffer-same-window (current-buffer))))
    output))

(provide 'health-chart-org)
;;; health-chart-org.el ends here
