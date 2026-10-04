;;; health-chart-template.el --- Chart templates and their placeholder syntax -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A TEMPLATE is a chart program written in a backend's own language
;; (a Vega-Lite JSON spec, a gnuplot script) with placeholders where the
;; chart spec's values go.  Templates live in DIR/BACKEND/KIND.EXT, DIR
;; being each of `health-chart-template-directories' and then the
;; bundled templates/ directory; the first match wins, so a user
;; template shadows the bundled one and a new file adds a new kind.
;;
;; Placeholder syntax:
;;
;;   {{PATH}}          the value at PATH in the chart spec, escaped for
;;                     the template's language
;;   {{PATH|FILTER}}   the same through FILTER: json, length, bare, data
;;
;; PATH is dot-separated member names of the spec (snake_case, as in
;; its JSON form): {{title}}, {{overlays.ref_low}}, {{colors.optimal}}.
;; A name applied to an array maps over its elements, so
;; {{legend.label}} is the array of every legend label; a number picks
;; one element ({{x.ticks.0.label}}).  {{data}} is the spec's rows.
;;
;; Escaping, by language:
;;
;;   json     every value as JSON: strings quoted, nil as null, arrays
;;            and objects encoded whole.
;;   gnuplot  strings as single-quoted literals (no backslash or
;;            backquote substitution), numbers bare, nil as NaN, arrays
;;            of scalars as array literals ['a', 'b'], arrays of
;;            objects as tab-separated datablock lines with a header.
;;   text     plain prose (Org report templates): strings as they are,
;;            line breaks as spaces, numbers compact, nil as nothing,
;;            arrays joined with ", ".
;;
;; Filters: `length' is an array's element count; `bare' inserts a
;; number or an identifier-like word unquoted (anything else is an
;; error); `json' forces JSON encoding; `data' forces datablock lines.
;; Text that is not a well-formed placeholder is copied unchanged.
;; Nothing is ever passed through a shell.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'health-chart-core)

(define-error 'health-chart-template-error
  "health-chart: template error" 'health-chart-error)

(defcustom health-chart-template-directories nil
  "Directories searched for chart templates before the bundled ones.
Each holds one subdirectory per backend (vega-lite/, gnuplot/) of files
named KIND.EXT (timeseries.vl.json, timeseries.gp).  A user template
shadows the bundled template of the same backend and kind; a template
for an unknown kind adds that kind for its backend."
  :type '(repeat directory)
  :group 'health-charts)

(defconst health-chart-template-bundled-directory
  (expand-file-name "templates" (file-name-directory (or load-file-name buffer-file-name
                                                         default-directory)))
  "The templates/ directory shipped with health-chart.")

(defconst health-chart-template--placeholder
  "{{[ \t]*\\([A-Za-z0-9_.-]+\\)[ \t]*\\(?:|[ \t]*\\([a-z]+\\)[ \t]*\\)?}}"
  "A placeholder: {{PATH}} or {{PATH|FILTER}}.")

(defun health-chart-template-directories ()
  "Every template directory in search order: the user's, then the bundled."
  (append (mapcar #'expand-file-name health-chart-template-directories)
          (list health-chart-template-bundled-directory)))

(defun health-chart-template-find (backend kind extension)
  "The template file for BACKEND and KIND with EXTENSION, or nil.
Searches `health-chart-template-directories' first, then the bundled."
  (seq-some (lambda (dir)
              (let ((file (expand-file-name (format "%s/%s%s" backend kind extension) dir)))
                (and (file-readable-p file) file)))
            (health-chart-template-directories)))

(defun health-chart-template-list (backend extension)
  "Templates of BACKEND with EXTENSION as ((KIND . FILE) ...), first match wins."
  (let (found)
    (dolist (dir (health-chart-template-directories))
      (let ((sub (expand-file-name (symbol-name backend) dir)))
        (when (file-directory-p sub)
          (dolist (file (directory-files sub t (concat (regexp-quote extension) "\\'")))
            (let ((kind (intern (string-remove-suffix extension (file-name-nondirectory file)))))
              (unless (assq kind found)
                (push (cons kind file) found)))))))
    (sort (nreverse found) (lambda (a b) (string< (car a) (car b))))))

(defun health-chart-template-read (file)
  "Contents of template FILE, read as UTF-8 (CRLF line ends become LF)."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (buffer-string)))

;; -----------------------------------------------------------------------
;; Paths
;; -----------------------------------------------------------------------

(defun health-chart-template--object-p (v)
  "Non-nil when V is a spec object (a plist with keyword keys)."
  (and (consp v) (keywordp (car v))))

(defun health-chart-template--member (object name)
  "(FOUND . VALUE) for member NAME of OBJECT; hyphens match underscores."
  (let ((key (intern (concat ":" (replace-regexp-in-string "-" "_" name)))))
    (if (plist-member object key)
        (cons t (plist-get object key))
      '(nil))))

(defun health-chart-template--step (value name)
  "(FOUND . RESULT) of path segment NAME applied to VALUE."
  (cond
   ((string-match-p "\\`[0-9]+\\'" name)
    (let ((i (string-to-number name)) (seq (append value nil)))
      (if (and (sequencep value) (not (stringp value)) (< i (length seq)))
          (cons t (nth i seq))
        '(nil))))
   ((health-chart-template--object-p value) (health-chart-template--member value name))
   ((vectorp value)
    (let ((results (mapcar (lambda (e) (health-chart-template--step e name)) value)))
      (if (cl-every #'car results)
          (cons t (apply #'vector (mapcar #'cdr results)))
        '(nil))))
   (t '(nil))))

(defun health-chart-template-lookup (context path)
  "(FOUND . VALUE) of dotted PATH in CONTEXT, a spec plist."
  (let ((result (cons t context)))
    (dolist (name (split-string path "\\." t))
      (when (car result)
        (setq result (health-chart-template--step (cdr result) name))))
    result))

;; -----------------------------------------------------------------------
;; Escaping
;; -----------------------------------------------------------------------

(defun health-chart-template--json (value)
  "VALUE encoded as compact JSON."
  (let ((json-encoding-pretty-print nil)
        (json-encoding-separator ","))
    (cond ((null value) "null")
          ((eq value t) "true")
          (t (json-encode value)))))

(defun health-chart-template--number (n)
  "Number N as a literal both JSON and gnuplot read."
  (cond ((integerp n) (number-to-string n))
        ((or (isnan n) (= n 1.0e+INF) (= n -1.0e+INF)) "NaN")
        ((= n (ftruncate n)) (format "%.1f" n))
        (t (let ((s (format "%.6g" n)))
             (if (string-match-p "[.e]" s) s (concat s ".0"))))))

(defun health-chart-template--gp-string (s)
  "S as a gnuplot single-quoted string literal.
Single quotes disable backslash escapes and backquote command
substitution; an embedded quote is doubled and line breaks become spaces."
  (concat "'" (replace-regexp-in-string
               "'" "''" (replace-regexp-in-string "[\n\r]" " " s t t) t t)
          "'"))

(defun health-chart-template--gp-scalar (v)
  "Scalar V as a gnuplot expression."
  (cond ((null v) "NaN")
        ((eq v t) "1")
        ((numberp v) (health-chart-template--number v))
        ((stringp v) (health-chart-template--gp-string v))
        ((symbolp v) (health-chart-template--gp-string (symbol-name v)))
        (t (signal 'health-chart-template-error
                   (list (format "cannot write %S as a gnuplot value" v)
                         :code "template_bad_value")))))

(defun health-chart-template--cell (v)
  "V as one datablock cell: no tabs, line breaks or backquotes."
  (cond ((null v) "NaN")
        ((eq v t) "1")
        ((numberp v) (health-chart-template--number v))
        (t (let ((s (replace-regexp-in-string "[\t\n\r]" " " (format "%s" v) t t)))
             (setq s (replace-regexp-in-string "`" "'" s t t))
             (if (string-empty-p s) "-" s)))))

(defun health-chart-template-datablock (rows)
  "ROWS (a sequence of spec objects) as tab-separated lines with a header.
Columns are the members of every row, in first-appearance order; a row
missing a member gets NaN.  Nested arrays and objects are skipped."
  (let (keys)
    (seq-doseq (row rows)
      (cl-loop for (k v) on row by #'cddr
               unless (or (memq k keys) (vectorp v) (health-chart-template--object-p v))
               do (push k keys)))
    (setq keys (nreverse keys))
    (let ((lines (cons (mapconcat (lambda (k) (substring (symbol-name k) 1)) keys "\t")
                       (mapcar (lambda (row)
                                 (mapconcat (lambda (k) (health-chart-template--cell (plist-get row k)))
                                            keys "\t"))
                               rows))))
      (when (member "EOD" lines)
        (signal 'health-chart-template-error
                (list "a datablock line reads EOD, which would end the block early"
                      :code "template_bad_value")))
      (string-join lines "\n"))))

(defun health-chart-template--gnuplot (value)
  "VALUE as gnuplot source."
  (cond
   ((vectorp value)
    (if (and (> (length value) 0) (health-chart-template--object-p (aref value 0)))
        (health-chart-template-datablock value)
      (concat "[" (mapconcat #'health-chart-template--gp-scalar value ", ") "]")))
   ((health-chart-template--object-p value)
    (signal 'health-chart-template-error
            (list "cannot write an object into gnuplot; name one of its members"
                  :code "template_bad_value")))
   (t (health-chart-template--gp-scalar value))))

(defun health-chart-template--text (value)
  "VALUE as plain text on one line."
  (cond ((null value) "")
        ((numberp value) (health-chart-fmt value))
        ((vectorp value) (mapconcat #'health-chart-template--text value ", "))
        (t (replace-regexp-in-string "[\n\r]+" " " (format "%s" value) t t))))

(defun health-chart-template-escape (value language &optional filter)
  "VALUE as source text in LANGUAGE (`json', `gnuplot' or `text'), through FILTER."
  (pcase filter
    ((or 'nil "") (pcase language
                    ('gnuplot (health-chart-template--gnuplot value))
                    ('text (health-chart-template--text value))
                    (_ (health-chart-template--json value))))
    ("json" (health-chart-template--json value))
    ("length" (number-to-string (length (if (sequencep value) value nil))))
    ("data" (health-chart-template-datablock (append value nil)))
    ("bare"
     (let ((s (if (numberp value) (health-chart-template--number value) (format "%s" (or value "")))))
       (unless (string-match-p "\\`[A-Za-z0-9_.#+-]*\\'" s)
         (signal 'health-chart-template-error
                 (list (format "|bare only inserts numbers and plain words, got %S" s)
                       :code "template_bad_value")))
       s))
    (_ (signal 'health-chart-template-error
               (list (format "unknown filter %S; use json, length, bare or data" filter)
                     :code "template_unknown_filter")))))

;; -----------------------------------------------------------------------
;; Fill
;; -----------------------------------------------------------------------

(defun health-chart-template-placeholders (text)
  "The distinct placeholder paths in template TEXT, in order."
  (let (paths (start 0))
    (while (string-match health-chart-template--placeholder text start)
      (cl-pushnew (match-string 1 text) paths :test #'equal)
      (setq start (match-end 0)))
    (nreverse paths)))

(defun health-chart-template-fill (text context language &optional file)
  "TEXT with every placeholder replaced from CONTEXT, escaped for LANGUAGE.
CONTEXT is a chart spec plist (plus any backend extras).  FILE names the
template in errors.  Signals `health-chart-template-error' for an
unknown path, naming the template and line."
  (let ((case-fold-search nil) (start 0) (parts nil))
    (while (string-match health-chart-template--placeholder text start)
      (let* ((mb (match-beginning 0)) (me (match-end 0))
             (path (match-string 1 text))
             (filter (match-string 2 text))
             (found (health-chart-template-lookup context path)))
        (unless (car found)
          (let ((line (1+ (cl-count ?\n (substring text 0 mb)))))
            (signal 'health-chart-template-error
                    (list (format "%s:%d: unknown placeholder {{%s}}; see docs/chartspec.md for the members a spec has"
                                  (if file (abbreviate-file-name file) "template") line path)
                          :code "template_unknown_variable" :path path :file file :line line))))
        (push (substring text start mb) parts)
        (push (health-chart-template-escape (cdr found) language filter) parts)
        (setq start me)))
    (push (substring text start) parts)
    (apply #'concat (nreverse parts))))

(provide 'health-chart-template)
;;; health-chart-template.el ends here
