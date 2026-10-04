;;; health-chart-org-base.el --- Org report options, parameters, queries and files -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Shared by the Org report modules: customization, block parameter
;; parsing, the pure query plans and asset file naming.

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

(defun health-chart-org--plot-line (params)
  "The #+PLOT line of a `health-table' with PARAMS."
  (format "#+PLOT: title:\"Latest values%s\" ind:1 deps:(2) type:2d with:histograms set:\"style fill solid 0.6\" set:\"xtics rotate by -45\""
          (let ((p (health-chart-org--person params))) (if p (format " · %s" p) ""))))

(defun health-chart-org--message (err)
  "The runbook message of ERR, on one line."
  (replace-regexp-in-string
   "[\n\r]+" " "
   (if (stringp (cadr err)) (cadr err) (error-message-string err))))

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

(provide 'health-chart-org-base)
;;; health-chart-org-base.el ends here
